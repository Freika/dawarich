require 'rails_helper'

RSpec.describe "Exports", type: :request do
  describe "GET /create" do
    before do
      sign_in create(:user)
    end

    it "returns http success" do
      get "/export"
      expect(response).to have_http_status(:success)
    end
  end
end
