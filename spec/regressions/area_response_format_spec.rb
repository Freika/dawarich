# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Area response format negotiation', type: :request do
  let(:user) { create(:user) }
  let(:attributes) { { name: 'Test Area', latitude: 52.52, longitude: 13.405, radius: 200 } }

  before { sign_in user }

  %w[text/html application/json application/xml].each do |accept|
    it "rejects #{accept} before creating an area or scheduling relabeling" do
      expect do
        post areas_path, params: attributes, headers: { 'Accept' => accept }
      end.not_to change(Area, :count)

      expect(response).to have_http_status(:not_acceptable)
      expect(enqueued_jobs.select { |job| job[:job] == Areas::RelabelVisitsJob }).to be_empty
    end

    it "rejects #{accept} before updating an area or scheduling relabeling" do
      area = create(:area, user:, name: 'Original', radius: 100)
      clear_enqueued_jobs

      patch area_path(area), params: attributes, headers: { 'Accept' => accept }

      expect(response).to have_http_status(:not_acceptable)
      expect(area.reload.name).to eq('Original')
      expect(area.radius).to eq(100)
      expect(enqueued_jobs.select { |job| job[:job] == Areas::RelabelVisitsJob }).to be_empty
    end
  end

  ['text/vnd.turbo-stream.html', 'text/html, text/vnd.turbo-stream.html', '*/*'].each do |accept|
    it "accepts #{accept} and creates an area" do
      expect do
        post areas_path, params: attributes, headers: { 'Accept' => accept }
      end.to change(Area, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    end
  end

  it 'returns not found for an unsupported-format update of another user\'s area' do
    area = create(:area, name: 'Private')

    patch area_path(area), params: attributes, headers: { 'Accept' => 'application/json' }

    expect(response).to have_http_status(:not_found)
    expect(area.reload.name).to eq('Private')
  end

  it 'returns not found for an unsupported-format update of a missing area' do
    patch area_path(0), params: attributes, headers: { 'Accept' => 'application/json' }

    expect(response).to have_http_status(:not_found)
  end
end
