# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family push rollout disabled', type: :request do
  let(:family) { create(:family) }
  let(:owner) { family.creator }
  let(:member) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{member.api_key}" } }

  before do
    create(:family_membership, :owner, family: family, user: owner)
    create(:family_membership, family: family, user: member)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('FAMILY_PUSH_ENABLED').and_return('true')
    allow(PushNotifications::Apns).to receive(:configured?).and_return(true)
    allow(PushNotifications::Fcm).to receive(:configured?).and_return(true)
  end

  it 'keeps capability and device registration disabled even with provider configuration' do
    get '/api/v1/families/mine', headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('push_notifications_enabled' => false, 'push_providers' => [],
                                            'history_before_sharing_supported' => true)
    put "/api/v1/push_subscriptions/#{SecureRandom.uuid}", headers: headers,
        params: { provider: 'apns', environment: 'production', push_token: 'a' * 64, context_id: SecureRandom.uuid }
    expect(response).to have_http_status(:service_unavailable)
    expect(PushSubscription.count).to eq(0)
  end

  it 'creates location requests without enqueueing push and ignores previously queued jobs' do
    request = nil
    expect do
      request = create(:family_location_request, family: family, requester: owner, target_user: member)
    end.not_to have_enqueued_job(Families::LocationRequestPushJob)
    subscription = PushSubscription.create!(user: member, provider: 'apns', environment: 'production',
                                            installation_id: SecureRandom.uuid, push_token: 'a' * 64,
                                            context_id: SecureRandom.uuid, expires_at: 30.days.from_now,
                                            api_key_digest: Digest::SHA256.hexdigest(member.api_key))
    allow(Families::PushNotification).to receive(:deliver)
    Families::LocationRequestPushJob.perform_now(request.id, subscription.id)
    expect(Families::PushNotification).not_to have_received(:deliver)
    delete "/api/v1/push_subscriptions/#{subscription.installation_id}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(PushSubscription.count).to eq(0)
  end
end
