# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'CORS preflight for POST /api/v1/imports/pending' do
  it 'returns 2xx with CORS headers for OPTIONS from dawarich.app' do
    process :options, '/api/v1/imports/pending', headers: {
      'HTTP_ORIGIN' => 'https://dawarich.app',
      'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST'
    }
    expect(response).to have_http_status(:no_content).or have_http_status(:ok)
    expect(response.headers['Access-Control-Allow-Origin']).to eq('https://dawarich.app')
  end

  it 'returns 2xx with CORS headers for OPTIONS from *.dawarich.pages.dev' do
    process :options, '/api/v1/imports/pending', headers: {
      'HTTP_ORIGIN' => 'https://preview-abc.dawarich.pages.dev',
      'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST'
    }
    expect(response.headers['Access-Control-Allow-Origin']).to eq('https://preview-abc.dawarich.pages.dev')
  end

  it 'does NOT include CORS headers for OPTIONS from disallowed origin' do
    process :options, '/api/v1/imports/pending', headers: {
      'HTTP_ORIGIN' => 'https://evil.example.com',
      'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST'
    }
    expect(response.headers['Access-Control-Allow-Origin']).to be_nil
  end
end
