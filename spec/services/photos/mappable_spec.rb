# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photos::Mappable do
  let(:photos) do
    [
      { id: 'a', latitude: 52.0, longitude: 13.0 },
      { id: 'b', latitude: nil, longitude: 13.0 },
      { id: 'c', latitude: 60.0, longitude: 10.0 }
    ]
  end

  it 'keeps only geotagged photos' do
    result = described_class.new(photos).call

    expect(result.map { _1[:id] }).to contain_exactly('a', 'c')
  end

  it 'rejects photos inside a privacy zone' do
    zones = [{ lat: 52.0, lon: 13.0, radius: 500 }]

    result = described_class.new(photos, privacy_zones: zones).call

    expect(result.map { _1[:id] }).to eq(['c'])
  end

  it 'caps the number of photos at the given max' do
    many = Array.new(5) { |i| { id: i, latitude: 1.0, longitude: 1.0 } }

    expect(described_class.new(many, max: 2).call.size).to eq(2)
  end

  it 'defaults the cap to MAX_PHOTOS' do
    many = Array.new(Photos::Mappable::MAX_PHOTOS + 10) { |i| { id: i, latitude: 1.0, longitude: 1.0 } }

    expect(described_class.new(many).call.size).to eq(Photos::Mappable::MAX_PHOTOS)
  end
end
