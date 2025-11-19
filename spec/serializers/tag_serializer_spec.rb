# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TagSerializer do
  let(:tag) { create(:tag, name: 'Home', icon: '🏠', color: '#4CAF50', privacy_radius_meters: 500) }
  let!(:place) { create(:place, name: 'My Place', latitude: 10.0, longitude: 20.0) }

  before do
    tag.places << place
  end

  subject { described_class.new(tag).call }

  it 'returns the correct JSON structure' do
    expect(subject).to eq({
      tag_id: tag.id,
      tag_name: 'Home',
      tag_icon: '🏠',
      tag_color: '#4CAF50',
      radius_meters: 500,
      places: [
        {
          id: place.id,
          name: 'My Place',
          latitude: 10.0,
          longitude: 20.0
        }
      ]
    })
  end
end
