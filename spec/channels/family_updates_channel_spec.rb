# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyUpdatesChannel, type: :channel do
  let(:owner) { create(:user, plan: :family, skip_auto_trial: true) }
  let(:family) { create(:family, creator: owner) }

  before do
    create(:family_membership, user: owner, family: family, role: :owner)
    stub_connection(family_api_user: owner, authorized_family_api_user: owner)
    allow(connection).to receive(:authorized_family_api_user).and_return(owner)
  end

  it 'subscribes to sharing changes and the existing point stream' do
    subscribe
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(family)
    expect(subscription).to have_stream_from(FamilyLocationsChannel.broadcasting_for(family))
  end

  it 'does not send periodic traffic without location changes' do
    subscribe
    subscription.send(:flush_location_change)
    expect(transmissions).to be_empty
  end

  it 'coalesces point updates into one small invalidation, without coordinates' do
    subscribe
    100.times { subscription.instance_variable_set(:@locations_changed, true) }
    subscription.send(:flush_location_change)
    subscription.send(:flush_location_change)
    expect(transmissions).to eq([{ 'type' => 'locations_changed' }])
  end

  it 'stops streaming when access or the API key is revoked' do
    subscribe
    allow(connection).to receive(:authorized_family_api_user).and_return(nil)
    subscription.instance_variable_set(:@locations_changed, true)
    subscription.send(:flush_location_change)
    expect(transmissions).to eq([{ 'type' => 'access_revoked' }])
    expect(subscription.streams).to be_empty
  end

  it 'does not follow a member into a different family on the old subscription' do
    subscribe
    other = create(:family)
    owner.family_membership.update!(family: other)
    owner.reload
    subscription.send(:verify_access)
    expect(transmissions.last).to eq({ 'type' => 'access_revoked' })
  end

  it 'rejects anonymous and ordinary session-only subscriptions' do
    stub_connection(family_api_user: nil)
    subscribe
    expect(subscription).to be_rejected
  end
end
