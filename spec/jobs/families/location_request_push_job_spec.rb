# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::LocationRequestPushJob, type: :job do
  let(:family) { create(:family) }
  let(:requester) { family.creator }
  let(:target) { create(:user) }
  let(:request) { create(:family_location_request, family: family, requester: requester, target_user: target) }
  let(:subscription) do
    PushSubscription.create!(user: target, installation_id: SecureRandom.uuid, context_id: SecureRandom.uuid,
                             provider: 'apns', environment: 'production', push_token: 'a' * 64,
                             api_key_digest: Digest::SHA256.hexdigest(target.api_key),
                             expires_at: 30.days.from_now)
  end

  before do
    create(:family_membership, :owner, family: family, user: requester)
    create(:family_membership, family: family, user: target)
    allow(PushSubscription).to receive(:enabled_providers).and_return(%w[apns fcm])
    allow(Families::PushNotification).to receive(:deliver).and_return(:sent)
  end

  it 'enqueues push after a request is persisted' do
    expect { request }.to have_enqueued_job(described_class)
  end

  it 'sends a generic alert with an account-bound destination' do
    described_class.perform_now(request.id, subscription.id)
    expect(Families::PushNotification).to have_received(:deliver).with(
      subscription,
      hash_including(data: hash_including(context_id: subscription.context_id, user_id: target.id),
                     body: 'A family member is requesting your location. Open Dawarich to respond.')
    )
  end

  it 'does not send stale requests, revoked API keys or requests after leaving the family' do
    request.update!(status: :declined)
    described_class.perform_now(request.id, subscription.id)
    request.update!(status: :pending)
    target.update!(api_key: SecureRandom.hex(16))
    described_class.perform_now(request.id, subscription.id)
    target.family_membership.destroy!
    described_class.perform_now(request.id, subscription.id)
    expect(Families::PushNotification).not_to have_received(:deliver)
  end

  it 'does not remove a registration renewed during delivery' do
    id = subscription.id
    allow(Families::PushNotification).to receive(:deliver) do
      subscription.update!(context_id: SecureRandom.uuid)
      :unregistered
    end
    described_class.perform_now(request.id, id)
    expect(PushSubscription.exists?(id)).to be true
  end

  it 'bounds delivery retries and does not let Sidekiq restart the retry cycle' do
    allow(Families::PushNotification).to receive(:deliver).and_raise(Families::PushNotification::DeliveryError)
    request_id = request.id
    subscription_id = subscription.id
    clear_enqueued_jobs
    expect(described_class.get_sidekiq_options['retry']).to be false
    job = described_class.new(request_id, subscription_id)
    3.times do
      expect { job.perform_now }.to have_enqueued_job(described_class)
      clear_enqueued_jobs
    end
    expect { job.perform_now }.to raise_error(Families::PushNotification::DeliveryError)
    expect(enqueued_jobs).to be_empty
    expect(Families::PushNotification).to have_received(:deliver).exactly(4).times
  end

  it 'skips expired requests and requests whose recipient already shares' do
    request.update!(expires_at: 1.minute.ago)
    described_class.perform_now(request.id, subscription.id)
    request.update!(expires_at: 1.hour.from_now)
    target.update_family_location_sharing!(true)
    described_class.perform_now(request.id, subscription.id)
    expect(Families::PushNotification).not_to have_received(:deliver)
  end

  it 'skips a departed family member even when their device registration is valid' do
    target.family_membership.destroy!
    described_class.perform_now(request.id, subscription.id)
    expect(Families::PushNotification).not_to have_received(:deliver)
  end

  it 'removes unregistered tokens' do
    allow(Families::PushNotification).to receive(:deliver).and_return(:unregistered)
    id = subscription.id
    described_class.perform_now(request.id, id)
    expect(PushSubscription.exists?(id)).to be false
  end
end
