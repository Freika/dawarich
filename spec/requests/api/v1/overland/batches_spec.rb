# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Overland::Batches', type: :request do
  describe 'POST /index' do
    let(:file_path) { 'spec/fixtures/files/overland/geodata.json' }
    let(:file) { File.open(file_path) }
    let(:json) { JSON.parse(file.read) }
    let(:params) { json }

    context 'with invalid api key' do
      it 'returns http unauthorized' do
        post '/api/v1/overland/batches', params: params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with valid api key' do
      let(:user) { create(:user) }

      it 'returns http success' do
        post "/api/v1/overland/batches?api_key=#{user.api_key}", params: params

        expect(response).to have_http_status(:created)
      end

      it 'enqueues a job' do
        expect do
          post "/api/v1/overland/batches?api_key=#{user.api_key}", params: params
        end.to have_enqueued_job(Overland::BatchCreatingJob)
      end

      context 'when user is inactive' do
        before do
          user.update(status: :inactive)
        end

        it 'returns http unauthorized' do
          post "/api/v1/overland/batches?api_key=#{user.api_key}", params: params

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end
end
