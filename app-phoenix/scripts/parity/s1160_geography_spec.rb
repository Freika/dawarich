# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261010120000_enqueue_achievement_visit_date_backfill')
require Rails.root.join('db/migrate/20261014120100_load_disputed_areas')

RSpec.describe 'Phoenix sync 1.16 geography Rails oracle' do
  it 'loads valid polygon pieces prunes excluded regions and enqueues one full backfill' do
    create(:region, code: 'UA-43')
    expect { EnqueueAchievementVisitDateBackfill.new.up }.not_to have_enqueued_job
    expect { LoadDisputedAreas.new.up }.to have_enqueued_job(DataMigrations::BackfillAchievementsJob).exactly(:once)
    expect(Region.where(code: 'UA-43')).to be_empty
    expect(DisputedArea.count).to be_positive
    expect(DisputedArea.where('NOT ST_IsValid(geom) OR ST_NPoints(geom)>256 OR ST_SRID(geom)<>4326')).to be_empty
  end

  it 'records moved UTC days through the current state storage interface' do
    actor = create(:user)
    source = create(:country, iso_a2: 'RU', iso_a3: 'RUS', name: 'Russia')
    target = create(:country, iso_a2: 'UA', iso_a3: 'UKR', name: 'Ukraine',
                              geom: 'MULTIPOLYGON (((33 44.5,35 44.5,35 46,33 46,33 44.5)))')
    point = create(:point, user: actor, timestamp: Time.utc(2025, 6, 1, 12).to_i, lonlat: 'POINT(34 45)')
    point.update_columns(country_id: source.id, country_name: 'Russia', country: 'provider')
    DataMigrations::ReassignBoundaryPointsJob.perform_now
    expect(point.reload.country_id).to eq(target.id)
    expect(point.country_name).to eq('Ukraine')
    expect(point[:country]).to eq('provider')
    expect(Stats::GeocodedDays.snapshot_month(actor, 2025, 6)).to have_key("#{actor.id}:2025-06-01")
  end
end
