# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Exports', type: :request do
  describe 'GET /download' do
    before do
      stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
        .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})

      sign_in create(:user)
    end

    it 'returns a success response with a file' do
      get export_download_path

      expect(response).to be_successful
      expect(response.headers['Content-Disposition']).to include('attachment')
    end
  end
end
