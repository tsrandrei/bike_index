class User < ActiveRecord::Base
  include ActionView::Helpers::SanitizeHelper
  include FeatureFlaggable
  cattr_accessor :current_user

  has_secure_password

  attr_accessor :my_bikes_link_target, :my_bikes_link_title, :current_password
  # stripe_id, is_paid_member, paid_membership_info

  mount_uploader :avatar, AvatarUploader

  has_many :ambassador_task_assignments
  has_many :ambassador_tasks, through: :ambassador_task_assignments
  has_many :payments
  has_many :subscriptions, -> { subscription }, class_name: "Payment"
  has_many :memberships, dependent: :destroy
  has_many :organization_embeds, class_name: "Organization", foreign_key: :auto_user_id
  has_many :organizations, through: :memberships
  has_many :ownerships, dependent: :destroy
  has_many :current_ownerships, -> { current }, class_name: "Ownership"
  has_many :owned_bikes, through: :ownerships, source: :bike
  has_many :currently_owned_bikes, through: :current_ownerships, source: :bike
  has_many :oauth_applications, class_name: "Doorkeeper::Application", as: :owner

  has_many :integrations, dependent: :destroy
  has_many :creation_states, inverse_of: :creator, foreign_key: :creator_id
  has_many :created_ownerships, class_name: "Ownership", inverse_of: :creator, foreign_key: :creator_id
  has_many :created_bikes, class_name: "Bike", inverse_of: :creator, foreign_key: :creator_id
  has_many :locks, dependent: :destroy
  has_many :user_emails, dependent: :destroy

  has_many :sent_stolen_notifications, class_name: "StolenNotification", foreign_key: :sender_id
  has_many :received_stolen_notifications, class_name: "StolenNotification", foreign_key: :receiver_id

  has_many :organization_invitations, class_name: "OrganizationInvitation", inverse_of: :inviter
  has_many :organization_invitations, class_name: "OrganizationInvitation", inverse_of: :invitee
  belongs_to :state
  belongs_to :country

  scope :confirmed, -> { where(confirmed: true) }
  scope :unconfirmed, -> { where(confirmed: false) }
  scope :superusers, -> { where(superuser: true) }
  scope :ambassadors, -> { where(id: Membership.ambassador_organizations.select(:user_id)) }

  validates_uniqueness_of :username, case_sensitive: false

  validates :password,
    presence: true,
    length: { within: 6..100 },
    on: :create
  validates_format_of :password, with: /\A.*(?=.*[a-z]).*\Z/i, message: "must contain at least one letter", on: :create

  validates :password,
    confirmation: true,
    length: { within: 6..100 },
    allow_blank: true,
    on: :update
  validates_format_of :password, with: /\A.*(?=.*[a-z]).*\Z/i, message: "must contain at least one letter", on: :update, allow_blank: true

  validate :preferred_language_is_an_available_locale

  validates_presence_of :email
  validates_uniqueness_of :email, case_sensitive: false

  before_validation :normalize_attributes
  validate :ensure_unique_email
  before_create :generate_username_confirmation_and_auth
  after_create :perform_create_jobs
  before_save :set_calculated_attributes

  attr_accessor :skip_geocode

  geocoded_by :address
  after_validation :geocode, if: lambda { !self.skip_geocode && self.geocodeable_attributes_changed? }

  class << self
    def fuzzy_email_find(email)
      UserEmail.confirmed.fuzzy_user_find(email)
    end

    def fuzzy_unconfirmed_primary_email_find(email)
      find_by_email(EmailNormalizer.normalize(email))
    end

    def fuzzy_confirmed_or_unconfirmed_email_find(email)
      fuzzy_email_find(email) || fuzzy_unconfirmed_primary_email_find(email)
    end

    def username_friendly_find(n)
      if n.is_a?(Integer) || n.match(/\A\d*\z/).present?
        where(id: n).first
      else
        find_by_username(n)
      end
    end

    def friendly_id_find(n)
      u = self.fuzzy_email_find(n)
      u && u.id
    end

    def admin_text_search(n)
      str = "%#{n.to_s.strip}%"
      joins(:user_emails)
        .where("users.name ILIKE ? OR users.email ILIKE ? OR user_emails.email ILIKE ?", str, str, str)
        .distinct
    end

    def from_auth(auth)
      return nil unless auth && auth.kind_of?(Array)
      self.where(id: auth[0], auth_token: auth[1]).first
    end
  end

  def additional_emails=(value)
    UserEmail.add_emails_for_user_id(id, value)
  end

  def secondary_emails
    user_emails.where.not(email: email).pluck(:email)
  end

  def ensure_unique_email
    return true unless self.class.fuzzy_confirmed_or_unconfirmed_email_find(email)
    return true if id.present? # Because existing users shouldn't see this error
    errors.add(:email, "That email is already signed up on Bike Index.")
  end

  def confirmed?; confirmed end

  def unconfirmed?; !confirmed? end

  def perform_create_jobs; AfterUserCreateWorker.new.perform(id, "new", user: self) end

  def superuser?; superuser end

  def developer?; developer end

  def ambassador?
    memberships.ambassador_organizations.any?
  end

  def to_param; username end

  def display_name; name.present? ? name : email end

  def donations; payments.sum(:amount_cents) end

  def donor?; donations > 900 end

  def paid_org?; organizations.paid.any? end

  def authorized?(obj)
    return true if superuser?
    return obj.authorized_for_user?(self) if obj.is_a?(Bike)
    return member_of?(obj) if obj.is_a?(Organization)
    false
  end

  def send_unstolen_notifications?
    superuser || organizations.any? { |o| o.paid_for?("unstolen_notifications") }
  end

  def reset_token_time
    t = password_reset_token && password_reset_token.split("-")[0]
    t = (t.present? && t.to_i > 1427848192) ? t.to_i : 1364777722
    Time.at(t)
  end

  def reset_token_expired?
    reset_token_time < (Time.current - 1.hours)
  end

  def set_password_reset_token(t = Time.current.to_i)
    self.password_reset_token = "#{t}-" + Digest::MD5.hexdigest("#{SecureRandom.hex(10)}-#{DateTime.current}")
    self.save
  end

  def accepted_vendor_terms_of_service?
    vendor_terms_of_service
  end

  def accepted_vendor_terms_of_service=(val)
    if ActiveRecord::Type::Boolean.new.type_cast_from_database(val)
      self.vendor_terms_of_service = true
      self.when_vendor_terms_of_service = Time.current
    end
    true
  end

  def send_password_reset_email
    unless reset_token_time > Time.current - 2.minutes
      set_password_reset_token
      EmailResetPasswordWorker.perform_async(id)
    end
  end

  def confirm(token)
    if token == confirmation_token
      self.confirmation_token = nil
      self.confirmed = true
      self.save
      AfterUserCreateWorker.new.perform(id, "confirmed", user: self)
      true
    end
  end

  def role(organization)
    m = Membership.where(user_id: id, organization_id: organization.id).first
    m && m.role
  end

  def member_of?(organization)
    return false unless organization.present?
    Membership.where(user_id: id, organization_id: organization.id).present? || superuser?
  end

  def admin_of?(organization)
    return false unless organization.present?
    Membership.where(user_id: id, organization_id: organization.id, role: "admin").present? || superuser?
  end

  def has_membership?
    memberships.any?
  end

  def has_police_membership?
    organizations.law_enforcement.any?
  end

  def has_shop_membership?
    organizations.bike_shop.any?
  end

  def default_organization
    return @default_organization if defined?(@default_organization) # Memoize, permit nil
    @default_organization = organizations&.first # Maybe at some point use memberships to get the most recent, for now, speed
  end

  def partner_sign_up
    partner_data && partner_data["sign_up"].present? ? partner_data["sign_up"] : nil
  end

  def bikes(user_hidden = true)
    Bike.unscoped
      .includes(:tertiary_frame_color, :secondary_frame_color, :primary_frame_color, :current_stolen_record)
      .where(id: bike_ids(user_hidden)).reorder(:created_at)
  end

  def rough_approx_bikes # Rough fix for users with large numbers of bikes
    Bike.includes(:ownerships).where(ownerships: { current: true, user_id: id }).reorder(:created_at)
  end

  def bike_ids(user_hidden = true)
    ows = ownerships.includes(:bike).where(example: false, current: true)
    if user_hidden
      ows = ows.map { |o| o.bike_id if o.user_hidden || o.bike }
    else
      ows = ows.map { |o| o.bike_id if o.bike }
    end
    ows.reject(&:blank?)
  end

  def current_subscription
    subscriptions.current.first
  end

  def delay_subscription_request
    update_attribute :make_subscription_request, false
    MarkForSubscriptionRequestWorker.perform_in(1.days, id)
  end

  def render_donation_request
    return nil unless has_police_membership? && !organizations.law_enforcement.paid.any?
    "law_enforcement"
  end

  def set_calculated_attributes
    self.title = strip_tags(title) if title.present?
    self.website = Urlifyer.urlify(website) if website.present?
    if my_bikes_link_target.present? || my_bikes_link_title.present?
      mbh = my_bikes_hash || {}
      mbh["link_target"] = Urlifyer.urlify(my_bikes_link_target) if my_bikes_link_target.present?
      mbh["link_title"] = my_bikes_link_title if my_bikes_link_title.present?
      self.my_bikes_hash = mbh
    end
    true
  end

  def mb_link_target
    my_bikes_hash && my_bikes_hash["link_target"]
  end

  def mb_link_title
    (my_bikes_hash && my_bikes_hash["link_title"]) || mb_link_target
  end

  def normalize_attributes
    self.phone = Phonifyer.phonify(phone) if phone
    self.username = Slugifyer.slugify(username) if username
    self.email = EmailNormalizer.normalize(email)
  end

  def userlink
    if show_bikes
      "/users/#{username}"
    elsif twitter.present?
      "https://twitter.com/#{twitter}"
    else
      ""
    end
  end

  def address(skip_default_country: false)
    country_string = country&.iso
    country_string = nil if skip_default_country && country_string == "US"
    [
      street,
      city,
      (state&.abbreviation),
      zipcode,
      country_string,
    ].reject(&:blank?).join(", ")
  end

  def address_hash
    return nil unless address.present?
    {
      address: street,
      city: city,
      state: (state&.abbreviation),
      zipcode: zipcode,
      country: country&.iso,
    }.as_json
  end

  def generate_auth_token
    begin
      self.auth_token = SecureRandom.urlsafe_base64 + "t#{Time.current.to_i}"
    end while User.where(auth_token: auth_token).exists?
  end

  def access_tokens_for_application(i)
    Doorkeeper::AccessToken.where(resource_owner_id: id, application_id: i)
  end

  protected

  def generate_username_confirmation_and_auth
    usrname = username || SecureRandom.urlsafe_base64
    while User.where(username: usrname).where.not(id: id).exists?
      usrname = SecureRandom.urlsafe_base64
    end
    self.username = usrname
    if !confirmed
      self.confirmation_token = (Digest::MD5.hexdigest "#{SecureRandom.hex(10)}-#{DateTime.current.to_s}")
    end
    generate_auth_token
    true
  end

  def geocodeable_attributes_changed?
    return false unless city.present? || zipcode.present? || street.present?
    city_changed? || zipcode_changed? || street_changed?
  end

  private

  def preferred_language_is_an_available_locale
    return if preferred_language.blank?
    return if I18n.available_locales.include?(preferred_language.to_sym)
    errors.add(:preferred_language, "not an available language")
  end
end
