# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/stats', type: :request do
  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  describe 'GET /index' do
    it 'renders a successful response' do
      get stats_url
      expect(response.status).to eq(302)
    end
  end
end
