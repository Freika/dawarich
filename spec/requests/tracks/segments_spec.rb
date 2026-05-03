# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tracks::Segments', type: :request do
  let(:user) { create(:user) }
  let(:track) { create(:track, user: user) }
  let!(:segment) do
    create(:track_segment, track: track, transportation_mode: :cycling,
           avg_speed: 15, max_speed: 18, avg_acceleration: 0.1, duration: 600,
           start_index: 0, end_index: 10)
  end

  before { sign_in user }

  describe 'GET /tracks/:track_id/segments' do
    it 'renders a Turbo Frame with one row per segment' do
      get track_segments_path(track)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("segment-row-#{segment.id}")
    end

    it 'returns 404 when accessing another user track' do
      other_track = create(:track, user: create(:user))
      get track_segments_path(other_track)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /tracks/:track_id/segments/:id' do
    it 'updates the segment mode and returns turbo-stream' do
      patch track_segment_path(track, segment),
            params: { track_segment: { transportation_mode: 'walking' } },
            headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include("segment-row-#{segment.id}")
      expect(segment.reload.transportation_mode).to eq('walking')
      expect(segment.corrected_at).to be_present
    end

    it 'returns 422 when mode is not in user allowlist' do
      user.settings['enabled_transportation_modes'] = %w[walking cycling]
      user.save!

      patch track_segment_path(track, segment),
            params: { track_segment: { transportation_mode: 'flying' } },
            headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(segment.reload.transportation_mode).to eq('cycling')
    end

    it 'resets to auto when reset=true' do
      segment.update!(transportation_mode: 'walking', corrected_at: 1.day.ago, source: 'user')

      patch track_segment_path(track, segment),
            params: { reset: 'true' },
            headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:ok)
      expect(segment.reload.corrected_at).to be_nil
      expect(segment.source).to eq('gps')
    end
  end
end
