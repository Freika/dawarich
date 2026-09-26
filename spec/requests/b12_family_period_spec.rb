# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'B12 Family callback period', type: :request do
  let(:owner) { create(:user, plan: :family, status: :active, active_until: 10.days.from_now, skip_auto_trial: true) }
  let(:family) { create(:family, creator: owner) }
  let(:member) { create(:user, plan: :lite, status: :inactive, active_until: nil, skip_auto_trial: true) }
  let(:paid_member) do
    create(:user, plan: :pro, status: :active, active_until: 90.days.from_now,
                  subscription_source: :paddle, skip_auto_trial: true)
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    stub_const('ENV', ENV.to_h.merge('JWT_SECRET_KEY' => 'b12_test_secret',
                                     'SUBSCRIPTION_WEBHOOK_SECRET' => 'b12_test_webhook'))
    ActiveJob::Base.queue_adapter = :test
    Rails.cache.clear
    create(:family_membership, :owner, user: owner, family: family)
    create(:family_membership, user: member, family: family)
    create(:family_membership, user: paid_member, family: family)
    Families::SyncMembers.new(family: family).call
  end

  def callback(event_id:, timestamp:, active_until:, status: 'active')
    payload = {
      event_id: event_id,
      event_timestamp_ms: timestamp,
      user_id: owner.id,
      plan: 'family',
      status: status,
      active_until: active_until.iso8601,
      subscription_source: 'paddle',
      exp: 5.minutes.from_now.to_i
    }
    token = JWT.encode(payload, 'b12_test_secret', 'HS256')
    perform_enqueued_jobs(only: Families::MemberSyncJob) do
      post '/api/v1/subscriptions/callback', params: { token: token },
                                             headers: { 'X-Webhook-Secret' => 'b12_test_webhook' }
    end
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)
  end

  it 'extends access, ignores replay and stale events, then lapses inherited access only' do
    first_end = 30.days.from_now.change(usec: 0)
    second_end = 45.days.from_now.change(usec: 0)

    callback(event_id: 'b12:first', timestamp: 1_000_000, active_until: first_end)
    expect(family.reload.access_until.to_i).to eq(first_end.to_i)
    expect(member.reload.active_until.to_i).to eq(first_end.to_i)
    expect(paid_member.reload.active_until).to be_future

    callback(event_id: 'b12:second', timestamp: 2_000_000, active_until: second_end)
    expect(family.reload.access_until.to_i).to eq(second_end.to_i)
    expect(member.reload.active_until.to_i).to eq(second_end.to_i)

    stale = callback(event_id: 'b12:second', timestamp: 2_000_000, active_until: 1.day.ago)
    expect(stale['message']).to eq('Stale event')
    stale = callback(event_id: 'b12:old', timestamp: 1_500_000, active_until: 1.day.ago)
    expect(stale['message']).to eq('Stale event')
    expect(family.reload.access_until.to_i).to eq(second_end.to_i)

    callback(event_id: 'b12:lapsed', timestamp: 3_000_000, active_until: 1.day.ago, status: 'inactive')
    expect(family.reload.access_live?).to be(false)
    expect(member.reload).to be_lite
    expect(paid_member.reload).to be_pro
    expect(paid_member).to be_active
    expect(enqueued_jobs.any? { |job| job[:job] == Families::LapseNotificationJob }).to be(true)

    get api_v1_plan_url(api_key: member.api_key)
    expect(JSON.parse(response.body).dig('features', 'sharing')).to be(false)
    get api_v1_plan_url(api_key: paid_member.api_key)
    expect(JSON.parse(response.body).dig('features', 'sharing')).to be(true)
  end
end
