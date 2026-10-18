# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared photo authorization after window edits', type: :request do
  let(:owner) { create(:user) }
  let(:trip) { create(:trip, user: owner, started_at: Time.utc(2026, 4, 1), ended_at: Time.utc(2026, 4, 14)) }
  let(:link) do
    create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id, settings: { 'show_photos' => true })
  end
  let(:photo) { { id: 'synthetic-asset', source: 'immich', latitude: 52.0, longitude: 13.0 } }

  before do
    allow(Photos::Search).to receive(:new).with(
      owner, start_date: trip.started_at.iso8601, end_date: trip.ended_at.iso8601
    ).and_return(instance_double(Photos::Search, call: [photo]))
    allow(Photos::Thumbnail).to receive(:new).and_return(
      instance_double(Photos::Thumbnail, call: instance_double(HTTParty::Response, success?: true, body: 'jpeg-bytes'))
    )
  end

  def prime_authorization
    get "/api/v1/shared/#{link.id}/photos"
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).map { |item| item['id'] }).to eq(['synthetic-asset'])
  end

  %i[started_at ended_at].each do |boundary|
    it "refuses a previously authorized thumbnail after #{boundary} excludes it" do
      prime_authorization
      trip.update!(boundary => Time.utc(2026, 4, 7))
      allow(Photos::Search).to receive(:new).with(
        owner, start_date: trip.started_at.iso8601, end_date: trip.ended_at.iso8601
      ).and_return(instance_double(Photos::Search, call: []))

      get "/api/v1/shared/#{link.id}/photos/synthetic-asset/thumbnail", params: { source: 'immich' }

      expect(response).to have_http_status(:not_found)
      expect(Photos::Thumbnail).not_to have_received(:new)
    end
  end

  it 'keeps grants bound to the window used by an in-flight provider search' do
    search = instance_double(Photos::Search)
    allow(Photos::Search).to receive(:new).and_return(search)
    allow(search).to receive(:call) do
      trip.update!(started_at: Time.utc(2026, 4, 7))
      [photo]
    end
    prime_authorization
    allow(search).to receive(:call).and_return([])

    get "/api/v1/shared/#{link.id}/photos/synthetic-asset/thumbnail", params: { source: 'immich' }

    expect(response).to have_http_status(:not_found)
    expect(Photos::Thumbnail).not_to have_received(:new)
  end

  it 'preserves cached authorization when the shared window has not changed' do
    prime_authorization
    expect(Photos::Search).not_to receive(:new)

    get "/api/v1/shared/#{link.id}/photos/synthetic-asset/thumbnail", params: { source: 'immich' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq('jpeg-bytes')
  end

  it 'refuses old thumbnails when the link is retargeted to another trip' do
    prime_authorization
    replacement = create(:trip, user: owner, started_at: Time.utc(2026, 5, 1), ended_at: Time.utc(2026, 5, 14))
    link.update!(resource_id: replacement.id)
    allow(Photos::Search).to receive(:new).with(
      owner, start_date: replacement.started_at.iso8601, end_date: replacement.ended_at.iso8601
    ).and_return(instance_double(Photos::Search, call: []))

    get "/api/v1/shared/#{link.id}/photos/synthetic-asset/thumbnail", params: { source: 'immich' }

    expect(response).to have_http_status(:not_found)
    expect(Photos::Thumbnail).not_to have_received(:new)
  end
end
