# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261013120000_reload_bundled_country_boundaries.rb')

RSpec.describe ReloadBundledCountryBoundaries do
  subject(:migration) { described_class.new }

  # Rows as seeded before the source change.
  let!(:ukraine) do
    create(:country, name: 'Ukraine', iso_a2: 'UA', iso_a3: 'UKR',
                     geom: 'MULTIPOLYGON (((30 50, 31 50, 31 51, 30 51, 30 50)))')
  end
  let!(:russia) do
    create(:country, name: 'Russia', iso_a2: 'RU', iso_a3: 'RUS',
                     geom: 'MULTIPOLYGON (((32 44, 37 44, 37 46.5, 32 46.5, 32 44)))')
  end

  it 'reloads both countries from the bundled source' do
    migration.up

    expect(Country.containing_point(34.10, 44.95)).to eq(ukraine)
    expect(Country.containing_point(33.50, 44.58)).to eq(ukraine)
    expect(Country.containing_point(37.62, 55.75)).to eq(russia)
  end

  it 'enqueues the point reassignment' do
    expect { migration.up }.to have_enqueued_job(DataMigrations::ReassignBoundaryPointsJob)
  end

  it 'skips installs whose countries are not seeded yet' do
    Country.delete_all

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::ReassignBoundaryPointsJob)
  end
end
