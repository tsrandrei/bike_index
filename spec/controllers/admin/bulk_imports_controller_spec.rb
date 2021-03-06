require "rails_helper"

RSpec.describe Admin::BulkImportsController, type: :controller do
  let(:user) { FactoryBot.create(:admin) }
  before do
    set_current_user(user)
  end

  describe "index" do
    let!(:bulk_import) { FactoryBot.create(:bulk_import) }
    it "renders" do
      get :index
      expect(response).to be_success
      expect(response).to render_template(:index)
      expect(flash).to_not be_present
    end
  end

  describe "show" do
    let!(:bulk_import) { FactoryBot.create(:bulk_import) }
    it "renders" do
      get :show, id: bulk_import.id
      expect(response).to be_success
      expect(response).to render_template(:show)
      expect(flash).to_not be_present
    end
  end

  describe "new" do
    it "renders" do
      get :new
      expect(response).to be_success
      expect(response).to render_template(:new)
      expect(flash).to_not be_present
      bulk_import = assigns(:bulk_import)
      expect(bulk_import.organization_id).to be_nil
      expect(bulk_import.no_notify).to be_falsey
    end
    context "passed params" do
      let(:organization) { FactoryBot.create(:organization) }
      it "includes them" do
        get :new, organization_id: organization.slug, no_notify: 1
        expect(response).to be_success
        expect(response).to render_template(:new)
        expect(flash).to_not be_present
        bulk_import = assigns(:bulk_import)
        expect(bulk_import.organization_id).to eq organization.id
        expect(bulk_import.no_notify).to be_truthy
      end
    end
  end

  describe "create" do
    context "valid create" do
      let(:organization) { FactoryBot.create(:organization) }
      let(:file) { Rack::Test::UploadedFile.new(File.open(File.join("public", "import_all_optional_fields.csv"))) }
      let(:valid_attrs) { { file: file, organization_id: organization.id, no_notify: "1" } }
      it "creates" do
        expect do
          post :create, bulk_import: valid_attrs
        end.to change(BulkImport, :count).by 1

        bulk_import = BulkImport.last
        expect(bulk_import.user).to eq user
        expect(bulk_import.file_url).to be_present
        expect(bulk_import.progress).to eq "pending"
        expect(bulk_import.organization).to eq organization
        expect(bulk_import.send_email).to be_falsey
        expect(BulkImportWorker).to have_enqueued_sidekiq_job(bulk_import.id)
      end
    end
  end

  describe "update" do
    let(:bulk_import) { FactoryBot.create(:bulk_import) }
    it "reenqueues" do
      Sidekiq::Worker.clear_all
      expect do
        put :update, id: bulk_import.id, reprocess: true
      end.to change(BulkImportWorker.jobs, :count).by 1
      expect(flash[:success]).to be_present
      expect(BulkImportWorker.jobs.map { |j| j["args"] }.flatten).to eq([bulk_import.id])
    end
  end
end
