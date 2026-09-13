# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::DemoData', type: :request do
  let!(:user) { create(:user) }
  let!(:api_key) { user.api_key }
  let(:headers) { { 'Authorization' => "Bearer #{api_key}" } }

  describe 'GET /api/v1/demo_data' do
    it 'returns 401 without an api key' do
      get '/api/v1/demo_data'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns exists: false when the user has no demo import' do
      get '/api/v1/demo_data', headers: headers

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['exists']).to be(false)
    end

    it 'returns exists: true when the user has a demo import' do
      create(:import, user: user, demo: true)

      get '/api/v1/demo_data', headers: headers

      expect(response.parsed_body['exists']).to be(true)
    end
  end

  describe 'POST /api/v1/demo_data' do
    it 'returns 401 without an api key' do
      post '/api/v1/demo_data'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 201 created when the importer seeds data' do
      importer = instance_double(DemoData::Importer, call: { status: :created })
      allow(DemoData::Importer).to receive(:new).with(user).and_return(importer)

      post '/api/v1/demo_data', headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['status']).to eq('created')
    end

    it 'returns 200 exists when demo data is already loaded' do
      importer = instance_double(DemoData::Importer, call: { status: :exists })
      allow(DemoData::Importer).to receive(:new).with(user).and_return(importer)

      post '/api/v1/demo_data', headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('exists')
    end

    it 'returns 422 on importer error' do
      importer = instance_double(DemoData::Importer, call: { status: :error })
      allow(DemoData::Importer).to receive(:new).with(user).and_return(importer)

      post '/api/v1/demo_data', headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['status']).to eq('error')
    end
  end

  describe 'DELETE /api/v1/demo_data' do
    it 'returns 401 without an api key' do
      delete '/api/v1/demo_data'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 destroyed when demo data is removed' do
      destroyer = instance_double(DemoData::Destroyer, call: { status: :destroyed })
      allow(DemoData::Destroyer).to receive(:new).with(user).and_return(destroyer)

      delete '/api/v1/demo_data', headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('destroyed')
    end

    it 'returns 200 no_demo_data when there is nothing to remove' do
      destroyer = instance_double(DemoData::Destroyer, call: { status: :no_demo_data })
      allow(DemoData::Destroyer).to receive(:new).with(user).and_return(destroyer)

      delete '/api/v1/demo_data', headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('no_demo_data')
    end

    it 'returns 422 on destroyer error' do
      destroyer = instance_double(DemoData::Destroyer, call: { status: :error })
      allow(DemoData::Destroyer).to receive(:new).with(user).and_return(destroyer)

      delete '/api/v1/demo_data', headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['status']).to eq('error')
    end
  end
end
