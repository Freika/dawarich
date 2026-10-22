# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family realtime broadcast survives upsert_all ingest path' do
  let(:family) { create(:family) }
  let(:owner) { family.creator }
  let(:sharer) { create(:user) }

  before do
    create(:family_membership, family: family, user: owner, role: :owner)
    create(:family_membership, family: family, user: sharer, role: :member)
    sharer.update_family_location_sharing!(true, duration: 'permanent')
    sharer.settings['live_map_enabled'] = true
    sharer.save!
  end

  let(:owntracks_payload) do
    {
      '_type' => 'location',
      'lat' => 52.6,
      'lon' => 13.6,
      'tst' => Time.zone.local(2026, 5, 20, 12, 0, 0).to_i,
      'batt' => 80,
      'acc' => 10
    }
  end

  it 'broadcasts to FamilyLocationsChannel when a point arrives via OwnTracks::PointCreator' do
    expect do
      OwnTracks::PointCreator.new(ActionController::Parameters.new(owntracks_payload).permit!, sharer.id).call
    end.to have_broadcasted_to(family).from_channel(FamilyLocationsChannel)
  end

  it 'carries the sharing user identity, coordinates, and timestamp in the broadcast payload' do
    broadcasts = []
    allow(FamilyLocationsChannel).to receive(:broadcast_to) do |target, payload|
      broadcasts << [target, payload]
    end

    OwnTracks::PointCreator.new(ActionController::Parameters.new(owntracks_payload).permit!, sharer.id).call

    expect(broadcasts.length).to eq(1)
    target, payload = broadcasts.first
    expect(target).to eq(family)
    expect(payload).to include(
      user_id: sharer.id,
      email: sharer.email,
      email_initial: sharer.email.first.upcase,
      latitude: 52.6,
      longitude: 13.6,
      timestamp: owntracks_payload['tst']
    )
  end

  it 'does not broadcast to FamilyLocationsChannel when the sharer has disabled family sharing' do
    sharer.update_family_location_sharing!(false)

    expect do
      OwnTracks::PointCreator.new(ActionController::Parameters.new(owntracks_payload).permit!, sharer.id).call
    end.not_to have_broadcasted_to(family).from_channel(FamilyLocationsChannel)
  end
end
