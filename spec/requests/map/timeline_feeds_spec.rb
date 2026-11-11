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

      context 'with a suggested visit that has no place suggestions' do
        let!(:bare_suggested) do
          create(:visit,
                 user: user,
                 place: nil,
                 name: 'Mystery Stop',
                 status: :suggested,
                 started_at: day + 9.hours,
                 ended_at: day + 10.hours,
                 duration: 3600)
        end

        it 'renders it as a plain visit row with an edit control, no confirm' do
          get map_timeline_feeds_path(start_at: day.iso8601, end_at: (day + 1.day).iso8601)

          expect(response).to have_http_status(:success)
          expect(response.body).to include('data-testid="visit-edit"')
          expect(response.body).not_to include('data-testid="visit-confirm"')
        end
      end

      context 'with a suggested visit that has a place' do
        let(:suggested_place) { create(:place, name: 'Cafe Central') }
        let!(:placed_suggested) do
          create(:visit,
                 user: user,
                 place: suggested_place,
                 name: 'Cafe Central',
                 status: :suggested,
                 started_at: day + 11.hours,
                 ended_at: day + 12.hours,
                 duration: 3600)
        end

        it 'renders identically to a confirmed visit — edit control, no review card' do
          get map_timeline_feeds_path(start_at: day.iso8601, end_at: (day + 1.day).iso8601)

          expect(response).to have_http_status(:success)
          expect(response.body).to include('data-testid="visit-edit"')
          expect(response.body).not_to include('data-testid="visit-confirm"')
          expect(response.body).not_to include('suggested-picker')
        end
      end

      context 'with a track that crosses midnight in the user timezone' do
        let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }
        let(:day_b) { Date.new(2026, 4, 28) }

        before do
          Time.use_zone('Europe/Berlin') do
            create(
              :track,
              user: user,
              start_at: Time.zone.local(2026, 4, 27, 23, 30),
              end_at: Time.zone.local(2026, 4, 28, 2, 0),
              distance: 180_000,
              duration: 9_000,
              dominant_mode: :driving
            )
          end
        end

        it 'renders the continuation card with arrival time and pro-rata distance copy' do
          get map_timeline_feeds_path(
            start_at: day_b.in_time_zone('Europe/Berlin').beginning_of_day.iso8601,
            end_at: day_b.in_time_zone('Europe/Berlin').end_of_day.iso8601
          )

          expect(response).to have_http_status(:success)
          expect(response.body).to include('continued from Apr 27, arrived')
          expect(response.body).to match(/\d+\.\d+ km of 180\.0 km/)
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

      it 'renders a slot for the selected point of this track' do
        track = create(:track, user: user)

        get track_info_map_timeline_feed_path(track)

        expect(response.body).to include(%(id="track-point-info-container-#{track.id}"))
      end

      it 'renders a Share button targeting the share-link-modal frame' do
        track = create(:track, user: user)

        get track_info_map_timeline_feed_path(track)

        expect(response.body).to include(new_track_share_link_path(track))
        expect(response.body).to include('share-link-modal')
      end
    end
  end

  describe 'privacy zones' do
    let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

    before do
      sign_in user
      home = create(:place, user:, name: 'Home', latitude: 52.444, longitude: 13.5, lonlat: 'POINT(13.5 52.444)')
      cafe = create(:place, user:, name: 'Cafe', latitude: 52.6, longitude: 13.7, lonlat: 'POINT(13.7 52.6)')
      tag = create(:tag, :privacy_zone, user:, privacy_radius_meters: 500)
      create(:tagging, tag:, taggable: home)
      create(:visit, user:, place: home, area: nil, name: 'Home', started_at: day + 7.hours, ended_at: day + 8.hours)
      create(:visit, user:, place: cafe, area: nil, name: 'Cafe', started_at: day + 10.hours,
                     ended_at: day + 11.hours)
    end

    it 'lists the in-zone visit without putting its coordinates on the page' do
      get map_timeline_feeds_path(start_at: day.iso8601, end_at: (day + 1.day).iso8601)

      page = Nokogiri::HTML(response.body)
      rows = page.css('[data-testid="visit-row"]').index_by { |row| row['aria-label'].split(' · ').first }
      bounds = JSON.parse(page.at_css('.timeline-day')['data-bounds'])

      expect(rows.keys).to contain_exactly('Home', 'Cafe')
      expect(rows['Home']['data-visit-lat']).to be_nil
      expect(rows['Cafe']['data-visit-lat']).to eq('52.6')
      expect(bounds['sw_lat']).to eq(52.6)
    end
  end

  describe 'local time of the place' do
    let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }
    let(:day) { Time.use_zone('Europe/Berlin') { Time.zone.parse('2025-01-15 00:00:00') } }
    let(:wichita) do
      create(:place, user:, name: 'Wichita', latitude: 37.69, longitude: -97.34, lonlat: 'POINT(-97.34 37.69)')
    end
    let(:berlin) do
      create(:place, user:, name: 'Berlin', latitude: 52.52, longitude: 13.40, lonlat: 'POINT(13.4 52.52)')
    end

    before do
      Timezone.create!(tzid: 'America/Chicago',
                       geom: 'SRID=4326;POLYGON((-100 37, -94.6 37, -94.6 40, -100 40, -100 37))')
      Timezone.create!(tzid: 'Europe/Berlin', geom: 'SRID=4326;POLYGON((6 47, 15 47, 15 55, 6 55, 6 47))')
      sign_in user
    end

    def page_for_day
      get map_timeline_feeds_path(start_at: day.iso8601, end_at: (day + 1.day).iso8601)
      Nokogiri::HTML(response.body)
    end

    it 'adds the time at the place to a visit in another time zone' do
      visit = create(:visit, user:, place: wichita, area: nil, name: 'Wichita',
                             started_at: day + 2.hours, ended_at: day + 3.hours, duration: 60)

      row = page_for_day.at_css("#visit_entry_#{visit.id}")
      expect(row.at_css('.visit-row__time').text.strip).to eq('02:00')
      expect(row.at_css('.timeline-local-time').text.strip).to eq('Jan 14, 19:00 local')
      expect(row['aria-label']).to include('Jan 14, 19:00 local')
    end

    it 'adds nothing to a visit in the account time zone' do
      visit = create(:visit, user:, place: berlin, area: nil, name: 'Berlin',
                             started_at: day + 9.hours, ended_at: day + 10.hours, duration: 60)

      row = page_for_day.at_css("#visit_entry_#{visit.id}")
      expect(row.at_css('.timeline-local-time')).to be_nil
      expect(row['aria-label']).not_to include('local')
    end

    it 'adds no local time to the rows that continue a visit or journey after midnight' do
      create(:visit, user:, place: wichita, area: nil, name: 'Wichita',
                     started_at: day + 20.hours, ended_at: day + 26.hours, duration: 360)
      create(:track, user:, start_at: day + 23.hours, end_at: day + 25.hours,
                     original_path: 'LINESTRING(-97.34 37.69, -97.2 37.8)')

      get map_timeline_feeds_path(start_at: (day + 1.day).iso8601, end_at: (day + 2.days).iso8601)
      next_day = Nokogiri::HTML(response.body)

      expect(next_day.css('.visit-row, .timeline-entry--journey').size).to eq(2)
      expect(next_day.css('.timeline-local-time')).to be_empty
    end

    it 'adds the time at the start to a journey that starts in another time zone' do
      create(:track, user:, start_at: day + 4.hours, end_at: day + 5.hours,
                     original_path: 'LINESTRING(-97.34 37.69, -97.2 37.8)')

      leg = page_for_day.at_css('.timeline-entry--journey')
      expect(leg.at_css('.journey-leg__time').text.strip).to eq('04:00')
      expect(leg.at_css('.timeline-local-time').text.strip).to eq('Jan 14, 21:00 local')
    end
  end
end
