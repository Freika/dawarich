# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Points::Motions', type: :request do
  let(:user) { create(:user) }
  let!(:point) { create(:point, user:, motion_data: { 'activity' => 'WALKING', 'action' => 'stationary_presence' }) }

  def repair(updates, api_key: user.api_key)
    patch '/api/v1/points/motion', params: { updates: },
                                    headers: { 'Authorization' => "Bearer #{api_key}" }, as: :json
  end

  it 'repairs only motion metadata and clears a stale activity scalar' do
    original = point.attributes.slice('lonlat', 'timestamp', 'raw_data', 'user_id', 'track_id')
    repair([{ id: point.id, motion: ['automotive'], latitude: 1, timestamp: 0 }])

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('updated_ids' => [point.id], 'missing_ids' => [])
    expect(point.reload.motion_data).to eq('motion' => ['automotive'], 'action' => 'stationary_presence')
    expect(point.attributes.slice(*original.keys)).to eq(original)
  end

  it 'does not recreate a deleted point, including a retry after deletion' do
    repair([{ id: point.id, motion: ['walking'] }])
    id = point.id
    point.reload.destroy!
    expect { repair([{ id:, motion: ['running'] }]) }.not_to change(Point, :count)
    expect(response.parsed_body).to eq('updated_ids' => [], 'missing_ids' => [id])
  end

  it 'preserves a server-relocated point and never inserts the original identity' do
    point.update!(lonlat: 'POINT(14 53)')
    expect { repair([{ id: point.id, motion: ['walking'] }]) }.not_to change(Point, :count)
    expect(point.reload.lon).to eq(14)
    expect(point.lat).to eq(53)
  end

  it 'does not update or disclose another account point' do
    other = create(:point)
    original = other.motion_data
    repair([{ id: other.id, motion: ['cycling'] }])
    expect(response.parsed_body).to eq('updated_ids' => [], 'missing_ids' => [other.id])
    expect(other.reload.motion_data).to eq(original)
  end

  it 'clears hints with an empty array and does not load archived raw data' do
    repair([{ id: point.id, motion: [] }])
    expect(response).to have_http_status(:ok)
    expect(point.reload.motion_data).to eq('motion' => [], 'action' => 'stationary_presence')
  end

  it 'rejects an invalid batch atomically' do
    repair([{ id: point.id, motion: ['running'] }, { id: point.id + 1, motion: ['teleporting'] }])
    expect(response).to have_http_status(:unprocessable_content)
    expect(point.reload.motion_data['motion']).to be_nil
  end

  it 'rejects duplicate IDs and oversized batches' do
    repair([{ id: point.id, motion: [] }] * 2)
    expect(response).to have_http_status(:unprocessable_content)
    repair(Array.new(1_001) { |i| { id: i + 1, motion: [] } })
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'rejects malformed bodies without an internal error' do
    [nil, {}, [], ['string'], [5], [{ id: '1', motion: [] }]].each do |updates|
      repair(updates)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it 'requires authentication' do
    repair([{ id: point.id, motion: [] }], api_key: 'invalid')
    expect(response).to have_http_status(:unauthorized)
  end

  it 'allows active Cloud Lite accounts to repair their ingested motion' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user.update_column(:plan, User.plans[:lite])
    repair([{ id: point.id, motion: ['walking'] }])
    expect(response).to have_http_status(:ok)
  end

  it 'rejects inactive accounts without changing metadata' do
    user.update_column(:active_until, 1.day.ago)
    repair([{ id: point.id, motion: ['walking'] }])
    expect(response).to have_http_status(:unauthorized)
    expect(point.reload.motion_data['motion']).to be_nil
  end

  it 'reclassifies affected tracks once and makes repeated hints idempotent' do
    track = create(:track, user:)
    point.update!(track:)
    expect { repair([{ id: point.id, motion: ['running'] }]) }
      .to have_enqueued_job(TransportationModes::ReclassifyTrackJob).with(track.id).once
    expect { repair([{ id: point.id, motion: ['running'] }]) }
      .not_to have_enqueued_job(TransportationModes::ReclassifyTrackJob)
  end
end
