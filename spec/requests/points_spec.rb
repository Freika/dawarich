require 'rails_helper'

RSpec.describe "Points", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/points/index"
      expect(response).to have_http_status(:success)
    end
  end

end
