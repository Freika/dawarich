# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports schedule track generation for the imported point range' do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:import) { create(:import, source: 'owntracks', status: 'created', user: user) }
  let(:file_path) { Rails.root.join('spec/fixtures/files/owntracks/2024-03.rec') }
  let(:service) { Imports::Create.new(user, import) }

  before do
    import.file.attach(
      io: File.open(file_path),
      filename: '2024-03.rec',
      content_type: 'application/octet-stream'
    )
  end

  it 'enqueues a parallel track generation job covering the imported range' do
    expect { service.call }.to have_enqueued_job(Tracks::ParallelGeneratorJob)
  end

  it 'covers exactly the timestamp range of imported points and runs in untracked-only bulk mode' do
    service.call

    min_ts, max_ts = import.reload.points.pick('MIN(timestamp), MAX(timestamp)')

    expect(Tracks::ParallelGeneratorJob).to have_been_enqueued.with(
      user.id,
      start_at: Time.zone.at(min_ts),
      end_at: Time.zone.at(max_ts),
      mode: :bulk,
      untracked_only: true
    )
  end

  context 'when the import produced no points' do
    let(:noop_importer) { instance_double(OwnTracks::Importer, call: nil) }

    before do
      allow(OwnTracks::Importer).to receive(:new).and_return(noop_importer)
    end

    it 'does not enqueue a track generation job' do
      expect { service.call }.not_to have_enqueued_job(Tracks::ParallelGeneratorJob)
    end
  end

  context 'when the import produced fewer than two points' do
    before do
      allow(OwnTracks::Importer).to receive(:new) do
        Class.new do
          def initialize(import, user_id, _file_path)
            @import = import
            @user_id = user_id
          end

          def call
            Point.create!(
              user_id: @user_id,
              import_id: @import.id,
              timestamp: 1_700_000_000,
              lonlat: 'POINT(13.33 52.22)'
            )
          end
        end.new(import, user.id, nil)
      end
    end

    it 'does not enqueue a track generation job' do
      expect { service.call }.not_to have_enqueued_job(Tracks::ParallelGeneratorJob)
    end
  end

  describe 'untracked-only semantics in the parallel generator' do
    it 'preserves existing tracks that overlap the import range and segments only untracked points into new tracks' do
      existing_track = create(
        :track,
        user: user,
        start_at: Time.zone.parse('2024-03-01T10:00:00Z'),
        end_at: Time.zone.parse('2024-03-01T11:00:00Z')
      )
      tracked_point = create(
        :point,
        user: user,
        track: existing_track,
        timestamp: Time.zone.parse('2024-03-01T10:30:00Z').to_i,
        lonlat: 'POINT(13.40 52.52)'
      )
      [
        Time.zone.parse('2024-03-01T15:00:00Z'),
        Time.zone.parse('2024-03-01T15:00:30Z'),
        Time.zone.parse('2024-03-01T15:01:00Z')
      ].each do |ts|
        create(:point, user: user, track: nil, timestamp: ts.to_i, lonlat: 'POINT(13.41 52.53)')
      end

      perform_enqueued_jobs do
        Tracks::ParallelGenerator.new(
          user,
          start_at: Time.zone.parse('2024-03-01T00:00:00Z'),
          end_at: Time.zone.parse('2024-03-02T00:00:00Z'),
          mode: :bulk,
          untracked_only: true
        ).call
      end

      expect(Track.exists?(existing_track.id)).to be(true)
      expect(tracked_point.reload.track_id).to eq(existing_track.id)
      expect(user.tracks.where.not(id: existing_track.id).exists?).to be(true)
    end

    it 'destroys overlapping tracks when untracked_only is false (default bulk semantics)' do
      existing_track = create(
        :track,
        user: user,
        start_at: Time.zone.parse('2024-03-01T10:00:00Z'),
        end_at: Time.zone.parse('2024-03-01T11:00:00Z')
      )

      Tracks::ParallelGenerator.new(
        user,
        start_at: Time.zone.parse('2024-03-01T00:00:00Z'),
        end_at: Time.zone.parse('2024-03-02T00:00:00Z'),
        mode: :bulk
      ).call

      expect(Track.exists?(existing_track.id)).to be(false)
    end
  end
end
