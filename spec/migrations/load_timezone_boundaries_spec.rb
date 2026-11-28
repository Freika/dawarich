# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261029150100_load_timezone_boundaries.rb')

RSpec.describe LoadTimezoneBoundaries do
  subject(:migration) { described_class.new }

  it 'loads the bundled time zone boundaries' do
    migration.up

    expect(Timezone.where('ST_Covers(geom, ST_SetSRID(ST_MakePoint(-97.34, 37.69), 4326))').pick(:tzid))
      .to eq('America/Chicago')
  end

  it 'replaces a partly loaded table when it runs again' do
    Timezone.create!(tzid: 'Etc/UTC', geom: 'SRID=4326;POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))')

    migration.up
    count = Timezone.count
    migration.up

    expect(Timezone.where(tzid: 'Etc/UTC').where('ST_Covers(geom, ST_SetSRID(ST_MakePoint(0.5, 0.5), 4326))'))
      .not_to exist
    expect(Timezone.count).to eq(count)
  end

  it 'lets the upgrade continue when the boundaries cannot be read' do
    allow(Zlib::GzipReader).to receive(:open).and_raise(Errno::ENOENT)

    expect { migration.up }.not_to raise_error
    expect(Timezone.count).to eq(0)
  end
end
