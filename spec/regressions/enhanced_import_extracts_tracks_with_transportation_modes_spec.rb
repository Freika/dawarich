# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enhanced import extracts tracks with transportation modes' do
  let(:user) do
    create(:user, settings: {
             'minutes_between_routes' => 30,
             'meters_between_routes' => 500
           })
  end
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }
  let(:base_time) { 1.hour.ago.to_i }

  before do
    10.times do |i|
      create(
        :point,
        user: user,
        import_id: import.id,
        tracker_id: 'phone',
        timestamp: base_time + (i * 60),
        lonlat: "POINT(#{13.405 + (i * 0.0001)} #{52.52 + (i * 0.0001)})"
      )
    end
  end

  let(:extracted_track) do
    EnhancedImport::Extracted::Track.new(
      tracker_id: 'phone',
      start_at: Time.zone.at(base_time),
      end_at:   Time.zone.at(base_time + 540),
      distance_m: 1500,
      transportation_mode: 'driving',
      confidence: 90,
      source_label: 'google_phone_takeout',
      segments: [
        EnhancedImport::Extracted::TrackSegment.new(
          start_index: 0,
          end_index: 9,
          transportation_mode: 'driving',
          confidence: 90,
          source_label: 'google_phone_takeout'
        )
      ]
    )
  end

  context 'when trust_source is true (default)' do
    before do
      allow_any_instance_of(EnhancedImport::Translator).to receive(:translate) do |&block|
        block.call(extracted_track)
      end
    end

    it 'creates one Track scoped to the tracker_id' do
      EnhancedImport::ExtractJob.new.perform(import.id)
      track = Track.last
      expect(track).to be_present
      expect(track.tracker_id).to eq('phone')
      expect(track.user_id).to eq(user.id)
    end

    it 'writes the source-app TrackSegment with the extraction source label' do
      EnhancedImport::ExtractJob.new.perform(import.id)
      track = Track.last
      segments = track.track_segments
      driving_segments = segments.where(source: 'google_phone_takeout')
      expect(driving_segments.count).to eq(1)
      expect(driving_segments.first.transportation_mode).to eq('driving')
    end

    it 'records counts on the import' do
      EnhancedImport::ExtractJob.new.perform(import.id)
      counts = import.reload.extraction_counts
      expect(counts[:tracks]).to eq(1)
      expect(counts[:segments]).to eq(1)
    end
  end

  context 'when trust_source is false' do
    before do
      import.update!(additional_data_extraction: { 'options' => { 'trust_source' => false } })
      allow_any_instance_of(EnhancedImport::Translator).to receive(:translate) do |&block|
        block.call(extracted_track)
      end
    end

    it 'creates the Track but skips writing source-app segments' do
      EnhancedImport::ExtractJob.new.perform(import.id)
      track = Track.last
      expect(track).to be_present
      expect(track.track_segments.where(source: 'google_phone_takeout').count).to eq(0)
    end
  end
end
