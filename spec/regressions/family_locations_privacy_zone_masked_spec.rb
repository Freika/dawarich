# frozen_string_literal: true

require 'rails_helper'

# Regression: family location sharing must apply each sharer's privacy-zone
# masker, so a point inside the sharer's privacy zone is not exposed to family.
RSpec.describe 'Family locations respect the sharer privacy zone' do
  let(:viewer) { create(:user) }
  let(:sharer) { create(:user) }

  before do
    allow(DawarichSettings).to receive(:family_feature_available_for?).and_return(true)
    family = create(:family, creator: viewer)
    create(:family_membership, :owner, family: family, user: viewer)
    create(:family_membership, family: family, user: sharer)
    viewer.reload
    sharer.reload
    sharer.update_family_location_sharing!(true, duration: 'permanent', share_history: true)

    place = create(:place, user: sharer, latitude: 52.52, longitude: 13.405)
    tag = create(:tag, user: sharer, privacy_radius_meters: 500)
    Tagging.create!(tag: tag, taggable: place)
  end

  it 'does not return a sharer point that falls inside the sharer privacy zone' do
    circle = Maps::PrivacyZoneMasker.new(sharer).send(:circles).first
    # The sharer's only point sits at the zone centre -> inside the zone.
    create(:point, user: sharer, lonlat: "POINT(#{circle.lon} #{circle.lat})",
                   timestamp: Time.utc(2024, 5, 1, 12).to_i)

    locations = Families::Locations.new(viewer).call
    mine = locations.find { |l| l[:user_id] == sharer.id }

    expect(mine).to be_nil # the in-zone latest point is masked away
  end

  it 'still returns a sharer point outside any privacy zone' do
    create(:point, user: sharer, lonlat: 'POINT(10.0 50.0)',
                   timestamp: Time.utc(2024, 5, 1, 12).to_i)

    locations = Families::Locations.new(viewer).call
    mine = locations.find { |l| l[:user_id] == sharer.id }

    expect(mine).to be_present
    expect(mine[:longitude]).to be_within(0.001).of(10.0)
  end
end
