# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, 'family realtime updates' do
  let(:owner) { create(:user, plan: :family, skip_auto_trial: true) }
  let(:family) { create(:family, creator: owner) }

  before do
    create(:family_membership, user: owner, family: family, role: :owner)
    allow(FamilyUpdatesChannel).to receive(:broadcast_to)
  end

  it 'notifies after enabling and disabling sharing, without sending coordinates' do
    owner.update_family_location_sharing!(true, duration: '1h')
    expect(FamilyUpdatesChannel).to have_received(:broadcast_to).with(family, type: 'sharing_changed').once
    owner.update_family_location_sharing!(false)
    expect(FamilyUpdatesChannel).to have_received(:broadcast_to).twice
  end

  it 'does not broadcast unrelated preference changes' do
    owner.update!(settings: owner.settings.merge('test_preference' => true))
    expect(FamilyUpdatesChannel).not_to have_received(:broadcast_to)
  end

  it 'does not publish a rolled-back sharing change' do
    User.transaction do
      owner.update_family_location_sharing!(true, duration: '1h')
      raise ActiveRecord::Rollback
    end
    expect(FamilyUpdatesChannel).not_to have_received(:broadcast_to)
  end

  it 'does not fail a sharing update if the broadcaster is unavailable' do
    allow(FamilyUpdatesChannel).to receive(:broadcast_to).and_raise(IOError)
    allow(ExceptionReporter).to receive(:call)
    expect { owner.update_family_location_sharing!(true, duration: '1h') }.not_to raise_error
    expect(owner.reload.family_sharing_enabled?).to be(true)
  end
end
