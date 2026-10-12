# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Anomaly-flagged points are excluded from bulk track generation' do
  let(:user) do
    create(:user, settings: {
             'minutes_between_routes' => 30,
             'meters_between_routes' => 500
           })
  end

  let(:chunk_start) { Time.zone.local(2026, 1, 1, 12, 0, 0).to_i }
  let(:chunk_end)   { Time.zone.local(2026, 1, 1, 12, 30, 0).to_i }

  let!(:clean_point_a) do
    create(:point, user: user, timestamp: chunk_start + 60,
                   latitude: 52.5200, longitude: 13.4050,
                   lonlat: 'POINT(13.4050 52.5200)', anomaly: false)
  end

  let!(:anomaly_point) do
    create(:point, user: user, timestamp: chunk_start + 120,
                   latitude: 52.5201, longitude: 13.4060,
                   lonlat: 'POINT(13.4060 52.5201)', anomaly: true)
  end

  let!(:clean_point_b) do
    create(:point, user: user, timestamp: chunk_start + 180,
                   latitude: 52.5202, longitude: 13.4070,
                   lonlat: 'POINT(13.4070 52.5202)', anomaly: false)
  end

  let(:chunk_data) do
    {
      chunk_id: 'spec-chunk',
      start_timestamp: chunk_start,
      end_timestamp: chunk_end,
      buffer_start_timestamp: chunk_start,
      buffer_end_timestamp: chunk_end,
      untracked_only: false
    }
  end

  before do
    session_manager = instance_double(Tracks::SessionManager, session_exists?: true, session_id: 'spec-session')
    allow(session_manager).to receive(:increment_completed_chunks)
    allow(session_manager).to receive(:increment_tracks_created)
    allow(session_manager).to receive(:mark_failed)
    allow(Tracks::SessionManager).to receive(:new).and_return(session_manager)
  end

  it 'does not assign track_id to anomaly points and omits their coords from track.original_path' do
    Tracks::TimeChunkProcessorJob.new.perform(user.id, 'spec-session', chunk_data)

    track = user.tracks.reload.first
    expect(track).to be_present

    aggregate_failures do
      expect(clean_point_a.reload.track_id).to eq(track.id)
      expect(clean_point_b.reload.track_id).to eq(track.id)
      expect(anomaly_point.reload.track_id).to be_nil

      path_coords = track.original_path.points.map { |p| [p.x.round(4), p.y.round(4)] }
      expect(path_coords).to contain_exactly([13.4050, 52.5200], [13.4070, 52.5202])
    end
  end
end
