require 'rails_helper'

RSpec.describe "Api::V1::Overland::Batches", type: :request do
  describe "POST /index" do
    let(:file_path) { 'spec/fixtures/files/overland/geodata.json' }
    let(:file) { File.open(file_path) }
    let(:json) { JSON.parse(file.read) }
    let(:params) { json }

    it 'returns http success' do
      post '/api/v1/overland/batches', params: params

      expect(response).to have_http_status(:created)
    end

    it 'enqueues a job' do
      expect do
        post '/api/v1/overland/batches', params: params
      end.to have_enqueued_job(Overland::BatchCreatingJob)
    end
  end
end
