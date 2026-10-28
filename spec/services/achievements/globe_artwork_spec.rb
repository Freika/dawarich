# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::GlobeArtwork do
  def card(key, evidence: Achievements::GeographicRegions::GROUPS.fetch(key))
    Achievements::Collectible.new(series: 'milestone', subject_key: key, level: 1,
                                  data: { 'evidence' => evidence.map { |region| { 'region' => region } } })
  end

  def bounds(path)
    points = path.scan(/[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?/).map(&:to_f).each_slice(2).to_a
    { xmin: points.map(&:first).min, xmax: points.map(&:first).max,
      ymin: points.map(&:last).min, ymax: points.map(&:last).max }
  end

  it 'keeps north/south and east/west divided in the correct geographic directions' do
    regions = described_class.assets.fetch('views').fetch('equatorial').fetch('regions')
    expect(bounds(regions.fetch('north'))[:ymax]).to be <= 0.001
    expect(bounds(regions.fetch('south'))[:ymin]).to be >= -0.001
    expect(bounds(regions.fetch('east'))[:xmin]).to be >= -0.001
    expect(bounds(regions.fetch('west'))[:xmax]).to be <= 0.001
    expect(bounds(regions.fetch('ne'))).to include(xmin: 0.0, ymax: 0.0)
    expect(bounds(regions.fetch('sw'))).to include(xmax: 0.0, ymin: 0.0)
  end

  it 'preserves continents, grid and different separators after both hemispheres are unlocked' do
    north_south = described_class.call(card('north_south'))
    east_west = described_class.call(card('east_west'))
    expect(north_south[:details].size).to eq(4)
    expect(north_south[:details][0][:path].length).to be > 1000
    expect(north_south[:details][1][:path]).to include('M', 'L')
    expect(north_south[:details][2][:path]).not_to eq(east_west[:details][2][:path])
    expect(north_south[:colors].pluck(:color).uniq.size).to eq(2)
    expect(north_south[:unvisited_path]).to be_empty
    expect(described_class.call(card('four_quarters'))[:colors].pluck(:color).uniq.size).to eq(4)
  end

  it 'lights only supported regions and keeps missing hemispheres dark without hiding the globe' do
    art = described_class.call(card('north_south', evidence: ['north']))
    view = described_class.assets.fetch('views').fetch('equatorial')
    expect(art[:colors].pluck(:path)).to eq([view.fetch('regions').fetch('north')])
    expect(art[:unvisited_path]).to eq(view.fetch('regions').fetch('south'))
    expect(art[:details].first[:path]).to eq(view.fetch('land'))
  end

  it 'uses tilted whole-globe views and masks everything outside the geographic polar cap' do
    %w[arctic antarctic].each do |pole|
      art = described_class.call(card(pole))
      view = described_class.assets.fetch('views').fetch(pole)
      cap = view.fetch('regions').fetch(pole)
      expect(art[:path]).to eq(view.fetch('sphere'))
      expect(art[:unvisited_path]).to eq("#{view.fetch('sphere')} #{cap}")
      expect(art[:colors].pluck(:path)).to eq([cap])
      expect(art[:details].first[:path]).not_to eq(described_class.assets.dig('views', 'equatorial', 'land'))
      expect(described_class.call(card(pole, evidence: []))[:unvisited_path]).to eq(view.fetch('sphere'))
    end
    expect(described_class.assets.fetch('polar_latitude')).to eq(Achievements::GeographicRegions::POLAR_LATITUDE)
  end
end
