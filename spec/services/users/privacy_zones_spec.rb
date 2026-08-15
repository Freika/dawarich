# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::PrivacyZones do
  let(:user) { create(:user) }

  it 'returns lon/lat/radius hashes for each place tagged as a privacy zone' do
    place = create(:place, user: user, latitude: 52.5, longitude: 13.4)
    tag = create(:tag, user: user, privacy_radius_meters: 300)
    create(:tagging, tag: tag, taggable: place)

    result = described_class.new(user).call

    expect(result).to contain_exactly(
      a_hash_including(lon: 13.4, lat: 52.5, radius: 300)
    )
  end

  it 'returns an empty array when the user has no privacy zones' do
    expect(described_class.new(user).call).to eq([])
  end
end
