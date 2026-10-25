# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261025120000_load_aosta_valley_region.rb')

RSpec.describe LoadAostaValleyRegion do
  subject(:migration) { described_class.new }

  it 'loads Aosta Valley before any recalculation can run' do
    create(:country)

    migration.up

    expect(Region.where(code: 'IT-23')).to exist
  end

  it 'skips loading on a fresh install without countries' do
    expect { migration.up }.not_to change(Region, :count)
  end

  it 'enqueues an achievements recalculation' do
    expect { migration.up }.to have_enqueued_job(DataMigrations::BackfillAchievementsJob)
  end

  it 'treats progress computed before Aosta Valley as stale' do
    create(:achievement_progress, achievement_key: Achievements::Progress::EXPLORATION_KEY,
                                  state: { 'calculation_version' => 6 })

    expect(Achievements::Progress.current_exploration).to be_empty
  end
end
