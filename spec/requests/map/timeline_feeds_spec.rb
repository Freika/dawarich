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

      describe 'on this day' do
        # The user's time zone is UTC; the dates below are days of that calendar.
        let(:today) { Time.now.utc.beginning_of_day }

        before do
          create(:note, user: user, body: 'One year back', noted_at: today - 1.year + 10.hours,
                        latitude: 52.5, longitude: 13.4)
          create(:note, user: user, body: 'Yesterday last year', noted_at: today - 1.year - 2.hours,
                        latitude: 52.5, longitude: 13.4)
          create(:note, user: user, body: 'Written today', noted_at: today + 1.hour, latitude: 52.5, longitude: 13.4)
        end

        it 'lists notes from the same date in earlier years when today is open' do
          get map_timeline_feeds_path(start_at: today.iso8601, end_at: (today + 1.day - 1.second).iso8601)

          block = Capybara.string(response.body).find('[data-testid=on-this-day]')
          expect(block).to have_text('One year back')
          expect(block).not_to have_text('Yesterday last year')
          expect(block).not_to have_text('Written today')
        end

        it 'is absent on any other day' do
          get map_timeline_feeds_path(start_at: (today - 1.day).iso8601, end_at: (today - 1.second).iso8601)

          expect(response.body).not_to include('on-this-day')
        end
      end

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

        context 'when the period covers several days' do
          let(:period) { { start_at: day.iso8601, end_at: (day + 2.days - 1.second).iso8601 } }

          before do
            create(:visit, user: user, place: place, name: 'Home', duration: 3600,
                           started_at: day + 1.day + 9.hours, ended_at: day + 1.day + 10.hours)
            create(:note, user: user, body: 'Rain all morning', noted_at: day + 11.hours,
                          latitude: 52.5, longitude: 13.4)
          end

          it 'reads like a diary: newest day first, each closed under its date with its notes in sight' do
            get map_timeline_feeds_path(period)

            page = Capybara.string(response.body)
            head = page.find('[data-testid=timeline-range-head]')
            expect(head).to have_text('January 15 – 16, 2025')
              .and have_text('2 days').and have_text('2 visits').and have_text('1 note')
            expect(head['data-range-start']).to eq('2025-01-15')

            days = page.all('[data-testid=timeline-diary-day]')
            expect(days.map { |d| d.find('details.timeline-day:not([open])')['data-day'] })
              .to eq(%w[2025-01-16 2025-01-15])
            expect(days.last.find('summary')).to have_text('15').and have_text('Wednesday')
            expect(days.last.find('.timeline-diary-notes')).to have_text('Rain all morning')
            # The day's own timeline is there too, folded.
            expect(days.last.find('details').text(:all)).to include('Home')
            expect(page).not_to have_css('[data-testid=day-prev]')
          end
        end

        describe 'searching the notes' do
          before do
            create(:note, user: user, body: 'Rain all morning', noted_at: day + 11.hours,
                          latitude: 52.5, longitude: 13.4)
            create(:note, user: user, body: 'Rain again, 100% wet', noted_at: day + 1.year + 12.hours,
                          latitude: 52.5, longitude: 13.4)
            create(:note, body: 'Rain on someone else', latitude: 1, longitude: 2)
          end

          def found(query)
            get map_timeline_feeds_path(start_at: day.iso8601, end_at: (day + 1.day).iso8601, q: query)
            Capybara.string(response.body).all('[data-testid=timeline-note-results] a')
          end

          it 'looks through every note of the user, whatever the period, newest first' do
            results = found('RAIN')

            expect(results.map(&:text)).to match([a_string_including('Rain again'), a_string_including('Rain all')])
            expect(results.first['href'])
              .to eq(map_v2_path(panel: 'timeline', month: '2026-01', date: '2026-01-15'))
          end

          it 'treats LIKE wildcards as plain characters' do
            expect(found('100%').map(&:text)).to match([a_string_including('Rain again')])
            expect(found('_')).to be_empty
          end

          it 'finds notes older than the Lite data window' do
            allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
            user.update!(plan: :lite)
            user.notes.find_by(body: 'Rain all morning').update!(noted_at: 3.years.ago)

            expect(found('all morning').size).to eq(1)
          end
        end

        it 'keeps a single day open, with its day navigator' do
          get map_timeline_feeds_path(start_at: day.iso8601, end_at: (day + 1.day).iso8601)

          page = Capybara.string(response.body)
          expect(page).to have_css('div.timeline-day [data-testid=day-prev]')
          expect(page).not_to have_css('details.timeline-day, [data-testid=timeline-range-head]')
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

      def days
        JSON.parse(response.body).fetch('days')
      end

      it 'describes every day of the month grid for the period picker' do
        create(:visit, user: user, started_at: Time.utc(2026, 4, 22, 9), ended_at: Time.utc(2026, 4, 22, 12),
                       duration: 180)
        create(:note, user: user, body: 'Written', noted_at: Time.utc(2026, 4, 10, 12), latitude: 52.5, longitude: 13.4)

        get calendar_map_timeline_feeds_path(month: '2026-04')

        expect(response).to have_http_status(:success)
        expect(days.size).to eq(42)
        expect(days['2026-04-22']).to include('heat' => a_value >= 1, 'noted' => false, 'disabled' => false)
        expect(days['2026-04-10']).to include('heat' => 0, 'noted' => true)
      end

      it 'defaults to the current month' do
        get calendar_map_timeline_feeds_path

        expect(days.keys).to include(Date.current.iso8601)
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
