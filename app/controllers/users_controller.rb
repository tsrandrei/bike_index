class UsersController < ApplicationController
  layout "application_revised"
  include Sessionable
  before_action :authenticate_user, only: [:edit]
  before_action :skip_if_signed_in, only: [:new, :globalid]
  before_action :assign_edit_template, only: [:edit, :update]

  def new
    @user ||= User.new(email: params[:email])
    render_partner_or_default_signin_layout
  end

  def globalid; end

  def create
    @user = User.new(permitted_parameters)
    if @user.save
      sign_in_and_redirect(@user)
    else
      @page_errors = @user.errors
      render_partner_or_default_signin_layout(render_action: :new)
    end
  end

  def please_confirm_email
    redirect_to(user_root_url) and return if current_user.present?
    @user = unconfirmed_current_user
    layout = sign_in_partner == "bikehub" ? "application_revised_bikehub" : "application_revised"
  end

  def confirm
    begin
      @user = User.find(params[:id])
      if @user.confirmed?
        flash[:success] = "Your user account is already confirmed. Please log in"
        render_partner_or_default_signin_layout(redirect_path: new_session_path)
      else
        if @user.confirm(params[:code])
          sign_in_and_redirect(@user)
        else
          render :confirm_error_bad_token
        end
      end
    rescue ActiveRecord::RecordNotFound
      render :confirm_error_404
    end
  end

  def request_password_reset
  end

  def update_password
    @user = current_user
  end

  def password_reset
    if params[:token].present?
      @user = User.find_by_password_reset_token(params[:token])
      if @user.present? && !@user.reset_token_expired?
        session[:return_to] = "password_reset"
        # They got the password reset email, which counts as confirming their email
        @user.confirm(@user.confirmation_token) if @user.unconfirmed?
        sign_in_and_redirect(@user)
      else
        flash[:error] = "We're sorry, but that link is no longer valid."
        render action: :request_password_reset
      end
    elsif params[:email].present?
      @user = User.fuzzy_confirmed_or_unconfirmed_email_find(params[:email])
      if @user.present?
        @user.send_password_reset_email
      else
        flash[:error] = "Sorry, that email address isn't in our system."
        render action: :request_password_reset
      end
    else
      redirect_to "/users/request_password_reset"
    end
  end

  def show
    user = User.find_by_username(params[:id])
    unless user
      raise ActionController::RoutingError.new("Not Found")
    end
    @owner = user
    @user = user
    unless user == current_user || @user.show_bikes
      redirect_to user_home_url, notice: "Sorry, that user isn't sharing their bikes" and return
    end
    @page = params[:page] || 1
    @per_page = params[:per_page] || 9
    bikes = user.bikes(true).page(@page).per(@per_page)
    @bikes = BikeDecorator.decorate_collection(bikes)
  end

  def edit
    @user = current_user
    @page_errors = @user.errors
  end

  def update
    @user = current_user
    if params[:user][:password_reset_token].present?
      if @user.password_reset_token != params[:user][:password_reset_token]
        remove_session
        flash[:error] = "Doesn't match user's password reset token"
        redirect_to user_home_url and return
      elsif @user.reset_token_expired?
        remove_session
        flash[:error] = "Password reset token expired, try resetting password again"
        redirect_to user_home_url and return
      end
    elsif params[:user][:password].present?
      unless @user.authenticate(params[:user][:current_password])
        @user.errors.add(:base, "Current password doesn't match, it's required for updating your password")
      end
    end
    if !@user.errors.any? && @user.update_attributes(permitted_update_parameters)
      AfterUserChangeWorker.perform_async(@user.id)
      if params[:user][:terms_of_service].present?
        if ActiveRecord::Type::Boolean.new.type_cast_from_database(params[:user][:terms_of_service])
          @user.terms_of_service = true
          @user.save
          flash[:success] = "Thanks! Now you can use Bike Index"
          redirect_to user_home_url and return
        else
          flash[:notice] = "You have to accept the Terms of Service if you would like to use Bike Index"
          redirect_to accept_terms_url and return
        end
      elsif params[:user][:vendor_terms_of_service].present?
        if ActiveRecord::Type::Boolean.new.type_cast_from_database(params[:user][:vendor_terms_of_service])
          @user.update_attributes(accepted_vendor_terms_of_service: true)
          if @user.memberships.any?
            flash[:success] = "Thanks! Now you can use Bike Index as #{@user.memberships.first.organization.name}"
          else
            flash[:success] = "Thanks for accepting the terms of service!"
          end
          redirect_to user_root_url and return
        else
          redirect_to accept_vendor_terms_path, notice: "You have to accept the Terms of Service if you would like to use Bike Index through an organization" and return
        end
      end
      if params[:user][:password].present?
        @user.generate_auth_token
        @user.set_password_reset_token
        @user.reload
        default_session_set(@user)
      end
      flash[:success] = "Your information was successfully updated."
      redirect_to my_account_url(page: params[:page]) and return
    end
    @page_errors = @user.errors.full_messages
    render action: :edit
  end

  def accept_terms
    if current_user.present?
      @user = current_user
    else
      redirect_to terms_url
    end
  end

  def accept_vendor_terms
    if current_user.present?
      @user = current_user
    else
      redirect_to vendor_terms_url
    end
  end

  def unsubscribe
    user = User.find_by_username(params[:id])
    user.update_attribute :notification_newsletters, false if user.present?
    flash[:success] = "You have been unsubscribed from Bike Index updates"
    redirect_to user_root_url and return
  end

  private

  def permitted_parameters
    params.require(:user)
          .permit(:name, :username, :email, :notification_newsletters, :notification_unstolen, :terms_of_service,
                  :additional_emails, :title, :description, :phone, :street, :city, :zipcode, :country_id,
                  :state_id, :avatar, :avatar_cache, :twitter, :show_twitter, :website, :show_website,
                  :show_bikes, :show_phone, :my_bikes_link_target, :my_bikes_link_title, :password,
                  :password_confirmation, :preferred_language)
          .merge(sign_in_partner.present? ? { partner_data: { sign_up: sign_in_partner } } : {})
  end

  def permitted_update_parameters
    pparams = permitted_parameters.except(:email, :password_reset_token)
    if pparams.keys.include?("username")
      pparams.delete("username") unless pparams["username"].present?
    end
    pparams
  end

  def edit_templates
    @edit_templates ||= {
      root: "User Settings",
      password: "Password",
      sharing: "Sharing + Personal Page",
    }.as_json
  end

  def assign_edit_template
    @edit_template = edit_templates[params[:page]].present? ? params[:page] : edit_templates.keys.first
  end
end
