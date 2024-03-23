require 'rails_helper'

RSpec.describe "/stats", type: :request do

  describe "GET /index" do
    it "renders a successful response" do
      get stats_url
      expect(response.status).to eq(302)
    end
  end
end
