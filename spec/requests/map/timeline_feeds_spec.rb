# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map::TimelineFeeds', type: :request do
  let(:user) { create(:user) }
  let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

  describe 'GET /map/timeline_feeds' do
    context 'when not signed in' do
      it 'redirects to sign in' do
        get map_timeline_feeds_path(start_at: day.iso8601, end_at: (day + 1.day).iso8601)

        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when signed in' do
      before { sign_in user }

      it 'returns http success with empty data' do
        get map_timeline_feeds_path(start_at: day.iso8601, end_at: (day + 1.day).iso8601)

        expect(response).to have_http_status(:success)
        expect(response.body).to include('No visits tracked this day')
      end

      context 'with visits and tracks' do
        let(:place) { create(:place, :with_geodata, name: 'Home', city: 'Berlin', country: 'Germany') }

        let!(:visit) do
          create(:visit,
                 user: user,
                 place: place,
                 name: 'Home',
                 started_at: day + 7.hours,
                 ended_at: day + 8.hours,
                 duration: 3600)
        end

        let!(:track) do
          create(:track,
                 user: user,
                 start_at: day + 8.hours,
                 end_at: day + 8.hours + 30.minutes,
                 distance: 8500,
                 duration: 1800,
                 dominant_mode: :cycling,
                 avg_speed: 17.0,
                 elevation_gain: 120,
                 elevation_loss: 80)
        end

        it 'renders day accordion with entries' do
          get map_timeline_feeds_path(start_at: day.iso8601, end_at: (day + 1.day).iso8601)

          expect(response).to have_http_status(:success)
          expect(response.body).to include('Wednesday, January 15')
          expect(response.body).to include('Home')
          expect(response.body).to include('cycled')
          expect(response.body).to include('8.5 km')
        end

        it 'includes Stimulus action attributes wired for timeline-feed controller' do
          get map_timeline_feeds_path(start_at: day.iso8601, end_at: (day + 1.day).iso8601)

          # The timeline-feed controller is now mounted on the settings panel wrapper
          # (app/views/map/maplibre/_settings_panel.html.erb). The feed partial renders
          # action attributes that target it.
          expect(response.body).to include('click->timeline-feed#')
        end

        it 'includes turbo-frame for track info' do
          get map_timeline_feeds_path(start_at: day.iso8601, end_at: (day + 1.day).iso8601)

          expect(response.body).to include("track-info-#{track.id}")
        end
      end
    end
  end

  describe 'GET /map/timeline_feeds/calendar' do
    context 'when not signed in' do
      it 'redirects to sign in' do
        get calendar_map_timeline_feeds_path

        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when signed in' do
      before { sign_in user }

      it 'returns 200 with the calendar turbo-frame' do
        get calendar_map_timeline_feeds_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include('turbo-frame id="timeline-calendar-frame"')
      end

      it 'renders the requested month and includes calendar day cells' do
        get calendar_map_timeline_feeds_path(month: '2026-04')

        expect(response).to have_http_status(:success)
        expect(response.body).to include('data-day="2026-04-22"')
        expect(response.body).to include('data-testid="calendar-day"')
        expect(response.body).to include('data-action="click->timeline-feed#selectDay"')
      end

      it 'applies heat-N class to each cell' do
        get calendar_map_timeline_feeds_path(month: '2026-04')

        expect(response.body).to match(/class="[^"]*heat-0[^"]*"/)
      end

      it 'includes previous/next month navigation' do
        get calendar_map_timeline_feeds_path(month: '2026-04')

        expect(response.body).to include('month=2026-03')
        expect(response.body).to include('month=2026-05')
      end
    end
  end

  describe 'GET /map/timeline_feeds/:id/track_info' do
    context 'when not signed in' do
      it 'redirects to sign in' do
        track = create(:track, user: user)
        get track_info_map_timeline_feed_path(track)

        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when signed in' do
      before { sign_in user }

      it 'renders track info for own track' do
        track = create(:track,
                       user: user,
                       distance: 5000,
                       avg_speed: 20.0,
                       elevation_gain: 100,
                       elevation_loss: 50,
                       dominant_mode: :cycling)

        get track_info_map_timeline_feed_path(track)

        expect(response).to have_http_status(:success)
        expect(response.body).to include('5.0 km')
        expect(response.body).to include('20.0 km/h')
        expect(response.body).to include('100 m')
        expect(response.body).to include('Cycling')
      end

      it 'returns 404 for other users track' do
        other_user = create(:user)
        track = create(:track, user: other_user)

        get track_info_map_timeline_feed_path(track)

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
