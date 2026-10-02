# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/api/v1/tracks/:track_id/segments', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }
  let(:track) { create(:track, user: user, dominant_mode: :cycling) }
  let!(:first_segment) do
    create(:track_segment, :anchored, track: track, transportation_mode: :cycling,
           start_at: Time.zone.parse('2025-01-01 10:00'), end_at: Time.zone.parse('2025-01-01 10:20'),
           distance: 5000, duration: 1200)
  end
  let!(:second_segment) do
    create(:track_segment, :anchored, track: track, transportation_mode: :walking,
           start_at: Time.zone.parse('2025-01-01 10:20'), end_at: Time.zone.parse('2025-01-01 10:25'),
           distance: 300, duration: 300)
  end

  def json
    JSON.parse(response.body)
  end

  describe 'GET /api/v1/tracks/:track_id/segments' do
    it 'returns the segments in order with the enabled modes' do
      get api_v1_track_segments_url(track), headers: headers

      expect(response).to have_http_status(:ok)
      expect(json['track_id']).to eq(track.id)
      expect(json['dominant_mode']).to eq('cycling')
      expect(json['enabled_modes']).to match_array(Track::TRANSPORTATION_MODES.keys.map(&:to_s))
      expect(json['segments'].pluck('id')).to eq([first_segment.id, second_segment.id])
      expect(json['segments'].first).to include(
        'transportation_mode' => 'cycling',
        'distance' => 5000,
        'duration' => 1200,
        'source' => 'inferred',
        'corrected_at' => nil,
        'manually_corrected' => false
      )
      expect(Time.zone.parse(json['segments'].first['start_at'])).to eq(first_segment.start_at)
      expect(Time.zone.parse(json['segments'].first['end_at'])).to eq(first_segment.end_at)
    end

    it 'lists only the modes the user has enabled' do
      user.settings['enabled_transportation_modes'] = %w[walking cycling driving]
      user.save!

      get api_v1_track_segments_url(track), headers: headers

      expect(json['enabled_modes']).to eq(%w[walking cycling driving])
    end

    it 'returns 404 for another user track' do
      other_track = create(:track, user: create(:user))

      get api_v1_track_segments_url(other_track), headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 without an API key' do
      get api_v1_track_segments_url(track)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/tracks/:track_id/segments/:id' do
    it 'applies a mode override and returns the updated track' do
      patch api_v1_track_segment_url(track, first_segment),
            params: { transportation_mode: 'driving' }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['segment']).to include(
        'id' => first_segment.id,
        'transportation_mode' => 'driving',
        'source' => 'user',
        'manually_corrected' => true
      )
      expect(json['segment']['corrected_at']).to be_present
      expect(json['dominant_mode']).to eq('driving')
      expect(json['segments'].pluck('transportation_mode')).to eq(%w[driving walking])
      expect(first_segment.reload.transportation_mode).to eq('driving')
      expect(track.reload.dominant_mode).to eq('driving')
    end

    it 'returns 422 mode_not_enabled for a mode outside the allowlist' do
      user.settings['enabled_transportation_modes'] = %w[walking cycling]
      user.save!

      patch api_v1_track_segment_url(track, first_segment),
            params: { transportation_mode: 'driving' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('mode_not_enabled')
      expect(json['enabled_modes']).to eq(%w[walking cycling])
      expect(first_segment.reload.transportation_mode).to eq('cycling')
    end

    it 'returns 422 mode_not_enabled for an unknown mode' do
      patch api_v1_track_segment_url(track, first_segment),
            params: { transportation_mode: 'hovercraft' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('mode_not_enabled')
    end

    it 'returns 400 when neither a mode nor reset is given' do
      patch api_v1_track_segment_url(track, first_segment), params: {}, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json['error']).to eq('missing_parameter')
    end

    it 'resets to auto-detection via the segment editor' do
      first_segment.update!(transportation_mode: 'driving', corrected_at: 1.day.ago, source: 'user')
      expect(Tracks::Reprocessor).to receive(:reprocess).with(track)

      patch api_v1_track_segment_url(track, first_segment),
            params: { reset: true }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['segment']).to be_nil
      expect(json).to include('dominant_mode', 'segments', 'enabled_modes')
      expect(first_segment.reload.corrected_at).to be_nil
    end

    it 'returns 422 reprocess_failed when re-detection fails' do
      first_segment.update!(transportation_mode: 'driving', corrected_at: 1.day.ago, source: 'user')
      allow(Tracks::Reprocessor).to receive(:reprocess).and_raise(StandardError, 'boom')
      allow(ExceptionReporter).to receive(:call)

      patch api_v1_track_segment_url(track, first_segment),
            params: { reset: true }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('reprocess_failed')
      expect(first_segment.reload.corrected_at).to be_present
    end

    it 'returns 404 for a segment of another user' do
      other_track = create(:track, user: create(:user))
      other_segment = create(:track_segment, track: other_track)

      patch api_v1_track_segment_url(other_track, other_segment),
            params: { transportation_mode: 'driving' }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(other_segment.reload.transportation_mode).to eq('driving')
    end

    it 'returns 404 for another user segment addressed through an own track' do
      other_segment = create(:track_segment, track: create(:track, user: create(:user)), transportation_mode: :walking)

      patch api_v1_track_segment_url(track, other_segment),
            params: { transportation_mode: 'driving' }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(other_segment.reload.transportation_mode).to eq('walking')
    end
  end
end
