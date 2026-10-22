# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260901070000_enqueue_country_code_collision_repair.rb')

RSpec.describe 'Country collision repair after dimension backfill' do
  include ActiveJob::TestHelper

  it 'repairs historical links even when the repair migration runs before source backfill' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    wrong = create(:country, name: 'US Naval Base Guantanamo Bay', iso_a2: 'US', iso_a3: 'USA')
    correct = create(:country, name: 'United States', iso_a2: 'US', iso_a3: 'USA')
    point = create(:point)
    point.update_columns(country_id: wrong.id, country_name: 'United States', country: 'United States', source_id: nil)
    unresolved = create(:point)
    unresolved.update_columns(country_id: nil, country_name: 'United States', country: 'United States', source_id: nil)
    expect(PointSource.count).to eq(0)

    perform_enqueued_jobs(only: DataMigrations::BackfillPointCountryIdJob) do
      EnqueueCountryCodeCollisionRepair.new.up
      DataMigrations::BackfillPointDimensionsJob.perform_now
    end

    expect(point.reload.source_id).to be_present
    expect(point.country_id).to eq(correct.id)
    expect(unresolved.reload.country_id).to eq(correct.id)
  end
end
