# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260925100100_reenqueue_transportation_mode_backfills.rb')

RSpec.describe ReenqueueTransportationModeBackfills do
  subject(:migration) { described_class.new }

  it 'restarts track classification and supported import backfills' do
    user = create(:user)
    create(:track, user:)
    supported_imports = %i[google_semantic_history owntracks google_records google_phone_takeout geojson]
                        .map { |source| create(:import, user:, source:) }
    create(:import, user:, source: :gpx)

    migration.up

    expect(DataMigrations::BackfillTransportationModesJob).to have_been_enqueued
    supported_imports.each do |import|
      expect(TransportationModes::ImportBackfillJob).to have_been_enqueued.with(import.id)
    end
    expect(TransportationModes::ImportBackfillJob).to have_been_enqueued.exactly(5).times
  end

  it 'enqueues nothing on a database without tracks or supported imports' do
    migration.up

    expect(DataMigrations::BackfillTransportationModesJob).not_to have_been_enqueued
    expect(TransportationModes::ImportBackfillJob).not_to have_been_enqueued
  end
end
