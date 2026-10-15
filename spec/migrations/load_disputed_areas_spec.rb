# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261014120100_load_disputed_areas.rb')

RSpec.describe LoadDisputedAreas do
  subject(:migration) { described_class.new }

  it 'loads the bundled disputed areas' do
    migration.up

    expect(DisputedArea.where('ST_Covers(geom, ST_SetSRID(ST_MakePoint(34.10, 44.95), 4326))')).to exist
  end

  it 'drops stored subdivisions that lie in disputed areas' do
    create(:region, code: 'UA-43')
    kept = create(:region, code: 'UA-30')

    migration.up

    expect(Region.all).to contain_exactly(kept)
  end

  it 'enqueues an achievements recalculation so existing progress drops the disputed areas' do
    expect { migration.up }.to have_enqueued_job(DataMigrations::BackfillAchievementsJob)
  end

  it 'treats progress computed before the disputed areas as stale' do
    create(:achievement_progress, achievement_key: Achievements::Progress::EXPLORATION_KEY,
                                  state: { 'calculation_version' => 4 })

    expect(Achievements::Progress.current_exploration).to be_empty
  end
end
