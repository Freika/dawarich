# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family history consent', type: :request do
  let(:owner) { create(:user) }
  let(:member) { create(:user) }
  let(:family) { create(:family, creator: owner) }
  let(:headers) { { 'Authorization' => "Bearer #{member.api_key}" } }

  before do
    create(:family_membership, :owner, family: family, user: owner)
    create(:family_membership, family: family, user: member)
  end

  def history
    get '/api/v1/families/locations/history', params: { start_at: 10.days.ago.iso8601, end_at: Time.current.iso8601 },
        headers: { 'Authorization' => "Bearer #{owner.api_key}" }
    expect(response).to have_http_status(:ok)
    response.parsed_body['members'].find { |row| row['user_id'] == member.id }&.fetch('points') || []
  end

  it 'keeps old consent restricted until explicitly including earlier history' do
    yesterday = create(:point, user: member, timestamp: 1.day.ago.to_i)
    create(:point, user: member, timestamp: 8.days.ago.to_i)
    patch '/api/v1/families/sharing', params: { enabled: true, share_history: true, history_window: '7d' },
headers: headers
    expect(history).to be_empty

    patch '/api/v1/families/sharing', params: { enabled: true, share_history: true, history_before_sharing: true },
headers: headers
    expect(response).to have_http_status(:ok)
    expect(history.map(&:last)).to eq([yesterday.timestamp])

    get '/api/v1/families/mine', headers: { 'Authorization' => "Bearer #{owner.api_key}" }
    metadata = response.parsed_body['members'].find { |row| row['user_id'] == member.id }
    expect(metadata).to include('share_history' => true, 'history_window' => '7d', 'history_before_sharing' => true)

    patch '/api/v1/families/sharing', params: { enabled: false }, headers: headers
    expect(history).to be_empty
    patch '/api/v1/families/sharing', params: { enabled: true, share_history: true }, headers: headers
    expect(history).to be_empty
    patch '/api/v1/families/sharing', params: { enabled: true, share_history: true, history_before_sharing: true },
headers: headers
    expect(history.map(&:last)).to eq([yesterday.timestamp])
  end

  it 'revokes earlier-history consent when history is disabled' do
    member.update_family_location_sharing!(true, share_history: true, history_before_sharing: true)
    patch '/api/v1/families/sharing', params: { enabled: true, share_history: false }, headers: headers
    expect(member.reload.family_history_before_sharing?).to be false
    expect(history).to be_empty
  end
end
