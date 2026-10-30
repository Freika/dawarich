# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exploration::CellGeometry do
  it 'preserves resolution nine and valid geometry at the dateline and both poles' do
    dataset = Exploration::Dataset.create!(version: "geometry-#{SecureRandom.hex(4)}", completed_at: Time.current)
    [[52.5, 13.3], [0, 179.99999], [0, -179.99999], [89.99999, 0], [-89.99999, 0]].each do |lat, lon|
      id = described_class.id(lat, lon)
      Exploration::Coverage.ensure!([id], dataset)
      result = ApplicationRecord.connection.select_one(<<~SQL)
        SELECT ST_IsValid(geom) valid, ST_Area(geom::geography) area FROM exploration_cells WHERE id='#{id}'
      SQL
      expect(result['valid']).to be(true)
      expect(result['area']).to be_between(1_000, 300_000)
    end
  end
end
