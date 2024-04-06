require 'rails_helper'

RSpec.describe "Imports", type: :request do
  describe "GET /imports" do
    context 'when user is logged in' do
      let(:user) { create(:user) }

      before do
        sign_in user
      end

      it "returns http success" do
        get imports_path

        expect(response).to have_http_status(200)
      end

      context 'when user has imports' do
        let!(:import) { create(:import, user: user) }

        it 'displays imports' do
          get imports_path

          expect(response.body).to include(import.name)
        end
      end
    end
  end

  describe "POST /imports" do
    context 'when user is logged in' do
      let(:user) { create(:user) }
      let(:file) { fixture_file_upload('owntracks/export.json', 'application/json') }

      before { sign_in user }

      it 'queues import job' do
        expect {
          post imports_path, params: { import: { source: 'owntracks', files: [file] } }
        }.to have_enqueued_job(ImportJob).on_queue('default').at_least(1).times
      end

      it 'creates a new import' do
        expect {
          post imports_path, params: { import: { source: 'owntracks', files: [file] } }
        }.to change(user.imports, :count).by(1)

        expect(response).to redirect_to(imports_path)
      end
    end
  end
end
