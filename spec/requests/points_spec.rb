require 'rails_helper'

RSpec.describe "Points", type: :request do
  describe "GET /index" do
    context 'when user signed in' do
      before do
        sign_in create(:user)
      end

      it "returns http success" do
        get points_path

        expect(response).to have_http_status(:success)
      end
    end

    context 'when user not signed in' do
      it "returns http success" do
        get points_path

        expect(response).to have_http_status(302)
      end
    end
  end
end
