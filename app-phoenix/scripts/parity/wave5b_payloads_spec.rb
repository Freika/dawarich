# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: wave 5b command payloads' do
  def wave5b_types
    %w[
      geocoding.reverse_point
      geocoding.reverse_place
      visits.suggest
      visits.full_history_redetect
      enhanced_import.extract_gpx
      enhanced_import.destroy_gpx
    ]
  end

  def capture(type)
    JobOutbox.where(command_type: type).delete_all
    yield
    JobOutbox.where(command_type: type).order(:created_at).map { |row| { 'type' => type, 'payload' => row.payload } }
  end

  it 'writes every Rails router payload for Phoenix to decode' do
    wave5b_types.each { |type| job_owner!("command:#{type}", :oban) }
    configure_instance_geocoding

    user = create(:user)
    point = create(:point, user:, reverse_geocoded_at: nil)
    place = create(:place, user:)
    extract_import = create(:import, user:, source: :gpx)
    destroy_import = create(:import, user:, source: :gpx)
    allow(EnhancedImport::CardBroadcaster).to receive(:call)

    payloads = []

    payloads += capture('geocoding.reverse_point') { ReverseGeocodingJob.new.perform('Point', point.id) }

    payloads += capture('geocoding.reverse_point') do
      Geocoding::ReverseCommands.enqueue_points(user.id, (1..100).to_a, force: true,
                                                                        producer: 'nightly_reverse_geocoding')
    end

    payloads += capture('geocoding.reverse_place') { ReverseGeocodingJob.new.perform('place', place.id) }

    payloads += capture('visits.suggest') do
      VisitSuggestingJob.perform_now(user_id: user.id, start_at: 2.days.ago, end_at: 1.day.ago)
    end

    payloads += capture('visits.full_history_redetect') { Visits::FullHistoryRedetectJob.new.perform(user.id) }

    payloads += capture('enhanced_import.extract_gpx') do
      EnhancedImport::ExtractJob.new.perform(extract_import.id, attempt: 1)
    end

    payloads += capture('enhanced_import.destroy_gpx') { EnhancedImport::DestroyJob.new.perform(destroy_import.id) }

    path = Rails.root.join('app-phoenix/test/fixtures/wave5b/payloads.json')
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{JSON.pretty_generate(payloads)}\n")

    expect(payloads.map { |row| row['type'] }.tally).to eq(
      'geocoding.reverse_point' => 2,
      'geocoding.reverse_place' => 1,
      'visits.suggest' => 1,
      'visits.full_history_redetect' => 1,
      'enhanced_import.extract_gpx' => 1,
      'enhanced_import.destroy_gpx' => 1
    )

    point_batches = payloads.select { |row| row['type'] == 'geocoding.reverse_point' }
                            .map { |row| row['payload']['point_ids'].length }.sort
    expect(point_batches).to eq([1, 100])
  end
end
