# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261010120000_enqueue_achievement_visit_date_backfill.rb')
require Rails.root.join('db/migrate/20261014120100_load_disputed_areas.rb')

RSpec.describe 'Achievement backfill when upgrading from 1.15.3' do
  it 'enqueues one full recalculation for both pending migrations' do
    expect do
      EnqueueAchievementVisitDateBackfill.new.up
      LoadDisputedAreas.new.up
    end.to have_enqueued_job(DataMigrations::BackfillAchievementsJob).exactly(:once)
  end
end
