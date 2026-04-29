# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Timeline::DayAssembler do
  let(:user) { create(:user) }
  let(:place) { create(:place, :with_geodata, name: 'Home', city: 'Berlin', country: 'Germany') }
  let(:place2) { create(:place, :with_geodata, name: 'Office', latitude: 52.52, longitude: 13.40) }

  describe '#call' do
    context 'with visits and tracks on the same day' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:visit1) do
        create(:visit,
               user: user,
               place: place,
               name: 'Home',
               started_at: day + 7.hours,
               ended_at: day + 8.hours,
               duration: 60) # minutes
      end

      let!(:track1) do
        create(:track,
               user: user,
               start_at: day + 8.hours,
               end_at: day + 8.hours + 30.minutes,
               distance: 8500,
               duration: 1800, # seconds (track.duration is in seconds)
               dominant_mode: :cycling)
      end

      let!(:visit2) do
        create(:visit,
               user: user,
               place: place2,
               name: 'Office',
               started_at: day + 8.hours + 30.minutes,
               ended_at: day + 17.hours,
               duration: 510) # minutes
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'returns one day entry' do
        expect(subject.length).to eq(1)
        expect(subject.first[:date]).to eq('2025-01-15')
      end

      it 'interleaves visits and tracks chronologically' do
        entries = subject.first[:entries]
        expect(entries.length).to eq(3)
        expect(entries[0][:type]).to eq('visit')
        expect(entries[0][:name]).to eq('Home')
        expect(entries[1][:type]).to eq('journey')
        expect(entries[1][:dominant_mode]).to eq('cycling')
        expect(entries[2][:type]).to eq('visit')
        expect(entries[2][:name]).to eq('Office')
      end

      it 'includes visit_id on visit entries' do
        entries = subject.first[:entries]
        visit_entry = entries.find { |e| e[:type] == 'visit' }
        expect(visit_entry[:visit_id]).to eq(visit1.id)
      end

      it 'includes track_id and metrics on journey entries' do
        entries = subject.first[:entries]
        journey = entries.find { |e| e[:type] == 'journey' }
        expect(journey[:track_id]).to eq(track1.id)
        expect(journey[:avg_speed]).to be_a(Float)
        expect(journey[:distance_unit]).to eq('km')
        expect(journey[:speed_unit]).to eq('km/h')
        expect(journey).to have_key(:elevation_gain)
        expect(journey).to have_key(:elevation_loss)
      end

      it 'calculates summary with distance and places' do
        summary = subject.first[:summary]
        expect(summary[:total_distance]).to eq(8.5)
        expect(summary[:distance_unit]).to eq('km')
        expect(summary[:places_visited]).to eq(2)
      end

      it 'calculates time breakdown' do
        summary = subject.first[:summary]
        expect(summary[:time_moving_minutes]).to eq(30)
        # visit1.duration = 60 (minutes), visit2.duration = 510 (minutes) -> 570 minutes
        expect(summary[:time_stationary_minutes]).to eq(570)
      end

      it 'time_stationary_minutes returns minutes not hours (regression for unit bug)' do
        # visit.duration is stored in MINUTES (see Visits::Creator / Visits::Create).
        # The previous implementation divided by 60 again, returning hours.
        summary = subject.first[:summary]
        total_visit_minutes = visit1.duration + visit2.duration
        expect(summary[:time_stationary_minutes]).to eq(total_visit_minutes)
      end

      it 'provides bounding box' do
        bounds = subject.first[:bounds]
        expect(bounds).to have_key(:sw_lat)
        expect(bounds).to have_key(:sw_lng)
        expect(bounds).to have_key(:ne_lat)
        expect(bounds).to have_key(:ne_lng)
      end

      it 'includes status on each visit entry' do
        entries = subject.first[:entries].select { |e| e[:type] == 'visit' }
        expect(entries).to all(have_key(:status))
        # visit factory defaults to 'suggested'
        expect(entries.first[:status]).to eq('suggested')
      end

      it 'includes place_id on each visit entry' do
        entry = subject.first[:entries].find { |e| e[:type] == 'visit' }
        expect(entry[:place_id]).to eq(visit1.place_id)
      end

      it 'includes editable_name as raw visit.name' do
        entry = subject.first[:entries].find { |e| e[:type] == 'visit' }
        expect(entry[:editable_name]).to eq(visit1.name)
        expect(entry[:editable_name]).to eq('Home')
      end

      it 'includes tags array (may be empty) on each visit entry' do
        entries = subject.first[:entries].select { |e| e[:type] == 'visit' }
        expect(entries).to all(have_key(:tags))
        expect(entries).to all(satisfy { |e| e[:tags].is_a?(Array) })
      end
    end

    context 'with a visit whose place has tags' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }
      let(:tag1) { create(:tag, user: user, name: 'Home', icon: '🏠', color: '#4CAF50') }
      let(:tag2) { create(:tag, user: user, name: 'Favorite', icon: '⭐', color: '#FFD700') }

      let!(:visit) do
        visit = create(:visit,
                       user: user,
                       place: place,
                       name: 'Home',
                       started_at: day + 10.hours,
                       ended_at: day + 12.hours,
                       duration: 120)
        place.tags << tag1
        place.tags << tag2
        visit
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'exposes each tag with id/name/icon/color' do
        entry = subject.first[:entries].first
        expect(entry[:tags]).to contain_exactly(
          { id: tag1.id, name: 'Home', icon: '🏠', color: '#4CAF50' },
          { id: tag2.id, name: 'Favorite', icon: '⭐', color: '#FFD700' }
        )
      end
    end

    context 'with a suggested visit that has suggested_places' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }
      let(:suggested_place_a) do
        create(:place, :with_geodata, name: 'Cafe Alpha', latitude: 52.5, longitude: 13.4)
      end
      let(:suggested_place_b) do
        create(:place, :with_geodata, name: 'Cafe Beta', latitude: 52.6, longitude: 13.5)
      end

      let!(:suggested_visit) do
        visit = create(:visit,
                       user: user,
                       place: place,
                       name: 'Suggested',
                       status: :suggested,
                       started_at: day + 10.hours,
                       ended_at: day + 12.hours,
                       duration: 120)
        visit.suggested_places << suggested_place_a
        visit.suggested_places << suggested_place_b
        visit
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'includes suggested_places on suggested visits' do
        entry = subject.first[:entries].first
        expect(entry[:suggested_places]).to contain_exactly(
          { id: place.id, name: 'Home', lat: place.lat, lng: place.lon },
          { id: suggested_place_a.id, name: 'Cafe Alpha', lat: suggested_place_a.lat, lng: suggested_place_a.lon },
          { id: suggested_place_b.id, name: 'Cafe Beta', lat: suggested_place_b.lat, lng: suggested_place_b.lon }
        )
      end
    end

    context 'with a suggested visit that has duplicate candidate names' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }
      let(:dup_a) do
        create(:place, :with_geodata, name: '1. FC Union Zapfstelle', latitude: 52.5, longitude: 13.4)
      end
      let(:dup_b) do
        create(:place, :with_geodata, name: '1. FC Union Zapfstelle', latitude: 52.51, longitude: 13.41)
      end
      let(:dup_c) do
        create(:place, :with_geodata, name: '  1. FC UNION ZAPFSTELLE  ', latitude: 52.52, longitude: 13.42)
      end
      let(:unique_place) do
        create(:place, :with_geodata, name: 'zapfLaden', latitude: 52.6, longitude: 13.5)
      end

      let!(:suggested_visit) do
        visit = create(:visit,
                       user: user,
                       place: place,
                       name: 'Suggested',
                       status: :suggested,
                       started_at: day + 10.hours,
                       ended_at: day + 12.hours,
                       duration: 120)
        visit.suggested_places << dup_a
        visit.suggested_places << dup_b
        visit.suggested_places << dup_c
        visit.suggested_places << unique_place
        visit
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'deduplicates candidates by normalized name, keeping the first occurrence' do
        entry = subject.first[:entries].first
        names = entry[:suggested_places].map { |p| p[:name] }
        expect(names).to eq(['Home', '1. FC Union Zapfstelle', 'zapfLaden'])
      end

      it 'preserves visit.place at index 0 and the first matching candidate for duplicates' do
        entry = subject.first[:entries].first
        expect(entry[:suggested_places].first[:id]).to eq(place.id)
        expect(entry[:suggested_places][1][:id]).to eq(dup_a.id)
      end
    end

    context 'with a confirmed visit' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:confirmed_visit) do
        create(:visit,
               user: user,
               place: place,
               name: 'Confirmed',
               status: :confirmed,
               started_at: day + 10.hours,
               ended_at: day + 12.hours,
               duration: 120)
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'does not include suggested_places key on non-suggested visits' do
        entry = subject.first[:entries].first
        expect(entry).not_to have_key(:suggested_places)
      end
    end

    context 'with points associated to a visit' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:visit) do
        create(:visit,
               user: user,
               place: place,
               name: 'Home',
               started_at: day + 10.hours,
               ended_at: day + 12.hours,
               duration: 120)
      end

      before do
        create_list(:point, 3, user: user, visit: visit)
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'includes point_count matching visit.points.size' do
        entry = subject.first[:entries].first
        expect(entry[:point_count]).to eq(3)
      end
    end

    context 'point_count is computed without materializing every Point row' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:visit_a) do
        create(:visit, user: user, place: place, name: 'A',
                       started_at: day + 8.hours, ended_at: day + 9.hours, duration: 60)
      end
      let!(:visit_b) do
        create(:visit, user: user, place: place, name: 'B',
                       started_at: day + 10.hours, ended_at: day + 11.hours, duration: 60)
      end

      before do
        create_list(:point, 50, user: user, visit: visit_a)
        create_list(:point, 50, user: user, visit: visit_b)
      end

      it 'returns the correct counts' do
        result = described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
        entries = result.first[:entries]
        expect(entries.find { |e| e[:name] == 'A' }[:point_count]).to eq(50)
        expect(entries.find { |e| e[:name] == 'B' }[:point_count]).to eq(50)
      end

      it 'does not load every Point row into memory (no SELECT * FROM points WHERE visit_id IN ...)' do
        eager_select_count = 0
        sub = lambda do |_name, _start, _finish, _id, payload|
          next if payload[:name].in?(%w[SCHEMA TRANSACTION])

          sql = payload[:sql].to_s
          eager_select_count += 1 if sql =~ /FROM "points".*"visit_id" IN/i && sql !~ /COUNT\(/i
        end

        ActiveSupport::Notifications.subscribed(sub, 'sql.active_record') do
          described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
        end

        expect(eager_select_count).to eq(0),
                                      'Expected no row-loading SELECT FROM points ' \
                                      "WHERE visit_id IN(...) without COUNT, but found #{eager_select_count}."
      end
    end

    context 'preloading (N+1 avoidance)' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }
      let(:tag) { create(:tag, user: user) }

      before do
        5.times do |i|
          p = create(:place, :with_geodata, name: "Place #{i}", latitude: 52.5 + i * 0.01, longitude: 13.4)
          p.tags << tag
          v = create(:visit,
                     user: user,
                     place: p,
                     name: "Visit #{i}",
                     status: :suggested,
                     started_at: day + (8 + i).hours,
                     ended_at: day + (9 + i).hours,
                     duration: 60)
          v.suggested_places << p
          create_list(:point, 2, user: user, visit: v)
        end
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601)
      end

      it 'preloads relations and keeps query count bounded' do
        # Warm the user lookup so the count reflects the assembler, not factory setup.
        user.reload

        query_count = 0
        counter = lambda do |_name, _start, _finish, _id, payload|
          query_count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION])
        end

        ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
          subject.call
        end

        expect(query_count).to be <= 18
      end
    end

    context 'summary status counts' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:suggested_visit) do
        create(:visit, user: user, place: place, name: 'A', status: :suggested,
                       started_at: day + 8.hours, ended_at: day + 9.hours, duration: 60)
      end
      let!(:confirmed_visit_1) do
        create(:visit, user: user, place: place, name: 'B', status: :confirmed,
                       started_at: day + 10.hours, ended_at: day + 11.hours, duration: 60)
      end
      let!(:confirmed_visit_2) do
        create(:visit, user: user, place: place, name: 'C', status: :confirmed,
                       started_at: day + 12.hours, ended_at: day + 13.hours, duration: 60)
      end
      let!(:declined_visit) do
        create(:visit, user: user, place: place, name: 'D', status: :declined,
                       started_at: day + 14.hours, ended_at: day + 15.hours, duration: 60)
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'includes suggested/confirmed/declined counts in summary' do
        summary = subject.first[:summary]
        expect(summary[:suggested_count]).to eq(1)
        expect(summary[:confirmed_count]).to eq(2)
        expect(summary[:declined_count]).to eq(1)
      end
    end

    context 'with only visits' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:visit) do
        create(:visit,
               user: user,
               place: place,
               name: 'Home',
               started_at: day + 10.hours,
               ended_at: day + 12.hours,
               duration: 120) # minutes
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'returns visit-only entries' do
        entries = subject.first[:entries]
        expect(entries.length).to eq(1)
        expect(entries.first[:type]).to eq('visit')
      end

      it 'reports zero moving time' do
        expect(subject.first[:summary][:time_moving_minutes]).to eq(0)
        expect(subject.first[:summary][:total_distance]).to eq(0.0)
      end
    end

    context 'with only tracks' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:track) do
        create(:track,
               user: user,
               start_at: day + 9.hours,
               end_at: day + 10.hours,
               distance: 15_000,
               duration: 3600,
               dominant_mode: :driving)
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'returns journey-only entries' do
        entries = subject.first[:entries]
        expect(entries.length).to eq(1)
        expect(entries.first[:type]).to eq('journey')
        expect(entries.first[:distance]).to eq(15.0)
      end

      it 'reports zero stationary time' do
        expect(subject.first[:summary][:time_stationary_minutes]).to eq(0)
        expect(subject.first[:summary][:places_visited]).to eq(0)
      end
    end

    context 'with empty date range' do
      subject do
        described_class.new(
          user,
          start_at: 1.year.ago.iso8601,
          end_at: 11.months.ago.iso8601
        ).call
      end

      it 'returns empty array' do
        expect(subject).to eq([])
      end
    end

    context 'with multi-day range' do
      let(:day1) { Time.zone.parse('2025-01-15 00:00:00') }
      let(:day2) { Time.zone.parse('2025-01-16 00:00:00') }

      let!(:visit_day1) do
        create(:visit,
               user: user,
               place: place,
               name: 'Home',
               started_at: day1 + 10.hours,
               ended_at: day1 + 12.hours,
               duration: 120) # minutes
      end

      let!(:visit_day2) do
        create(:visit,
               user: user,
               place: place2,
               name: 'Office',
               started_at: day2 + 9.hours,
               ended_at: day2 + 17.hours,
               duration: 480) # minutes
      end

      subject do
        described_class.new(
          user,
          start_at: day1.iso8601,
          end_at: (day2 + 1.day).iso8601
        ).call
      end

      it 'returns one entry per day sorted ascending' do
        expect(subject.length).to eq(2)
        expect(subject[0][:date]).to eq('2025-01-15')
        expect(subject[1][:date]).to eq('2025-01-16')
      end
    end

    context 'with visits without places' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:visit) do
        create(:visit,
               user: user,
               place: nil,
               name: 'Unknown',
               started_at: day + 10.hours,
               ended_at: day + 12.hours,
               duration: 120) # minutes
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'handles visits without places gracefully' do
        entry = subject.first[:entries].first
        expect(entry[:type]).to eq('visit')
        expect(entry[:name]).to eq('Unknown')
        expect(entry[:place]).to be_nil
      end
    end

    context 'with user timezone driving day grouping' do
      # The assembler MUST group by the user's configured timezone
      # (user.safe_settings.timezone), not by the server's Time.zone.
      # Regression: visits at 23:30 UTC for a Europe/Berlin user must be grouped
      # on the NEXT local day (Jan 16), not Jan 15.

      let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }
      let(:utc_late) { Time.utc(2026, 4, 22, 23, 30, 0) }

      let!(:late_visit) do
        create(:visit,
               user: user,
               place: place,
               name: 'Late Visit',
               started_at: utc_late,
               ended_at: utc_late + 1.hour,
               duration: 60)
      end

      # Wrap the outer Time.zone in UTC to prove the user's setting wins over the process timezone.
      around do |example|
        Time.use_zone('UTC') { example.run }
      end

      subject do
        described_class.new(
          user,
          start_at: '2026-04-22T00:00:00+02:00',
          end_at: '2026-04-24T00:00:00+02:00'
        ).call
      end

      it 'groups a 23:30 UTC visit on the next day in the user timezone' do
        visit_day = subject.find { |d| d[:entries].any? { |e| e[:name] == 'Late Visit' } }
        expect(visit_day).not_to be_nil
        expect(visit_day[:date]).to eq('2026-04-23')
      end
    end

    context 'with timezone boundary — event near midnight UTC' do
      # A visit that starts at 23:30 UTC is still Jan 15 in UTC,
      # but already Jan 16 in UTC+1 (Europe/Berlin).
      # DayAssembler must group by the USER's configured timezone
      # (user.safe_settings.timezone), independent of the server Time.zone.

      let(:utc_late) { Time.utc(2025, 1, 15, 23, 30, 0) }

      let!(:late_visit) do
        create(:visit,
               user: user,
               place: place,
               name: 'Late Visit',
               started_at: utc_late,
               ended_at: utc_late + 1.hour,
               duration: 60) # minutes
      end

      context 'when user timezone is UTC' do
        let(:user) { create(:user, settings: { 'timezone' => 'UTC' }) }

        subject do
          described_class.new(
            user,
            start_at: '2025-01-15T00:00:00Z',
            end_at: '2025-01-16T23:59:59Z'
          ).call
        end

        it 'groups the visit on January 15' do
          visit_day = subject.find { |d| d[:entries].any? { |e| e[:name] == 'Late Visit' } }
          expect(visit_day[:date]).to eq('2025-01-15')
        end
      end

      context 'when user timezone is UTC+1 (Europe/Berlin)' do
        let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }

        subject do
          described_class.new(
            user,
            start_at: '2025-01-15T00:00:00+01:00',
            end_at: '2025-01-17T00:00:00+01:00'
          ).call
        end

        it 'groups the visit on January 16 (next day in Berlin)' do
          visit_day = subject.find { |d| d[:entries].any? { |e| e[:name] == 'Late Visit' } }
          expect(visit_day[:date]).to eq('2025-01-16')
        end
      end
    end

    context 'with timezone boundary — track spanning midnight' do
      let(:before_midnight) { Time.utc(2025, 1, 15, 23, 0, 0) }

      let!(:midnight_track) do
        create(:track,
               user: user,
               start_at: before_midnight,
               end_at: before_midnight + 2.hours,
               distance: 5000,
               duration: 7200,
               dominant_mode: :driving)
      end

      context 'when user timezone is US Eastern (UTC-5)' do
        let(:user) { create(:user, settings: { 'timezone' => 'Eastern Time (US & Canada)' }) }

        subject do
          described_class.new(
            user,
            start_at: '2025-01-15T00:00:00-05:00',
            end_at: '2025-01-16T23:59:59-05:00'
          ).call
        end

        it 'groups the track by its start_at date in Eastern time (Jan 15)' do
          track_day = subject.find { |d| d[:entries].any? { |e| e[:type] == 'journey' } }
          # 23:00 UTC = 18:00 Eastern, still Jan 15
          expect(track_day[:date]).to eq('2025-01-15')
        end
      end

      context 'when user timezone is UTC+9 (Tokyo)' do
        let(:user) { create(:user, settings: { 'timezone' => 'Tokyo' }) }

        subject do
          described_class.new(
            user,
            start_at: '2025-01-15T00:00:00+09:00',
            end_at: '2025-01-17T00:00:00+09:00'
          ).call
        end

        it 'groups the track on January 16 (next day in Tokyo)' do
          track_day = subject.find { |d| d[:entries].any? { |e| e[:type] == 'journey' } }
          # 23:00 UTC = 08:00+1 JST = Jan 16
          expect(track_day[:date]).to eq('2025-01-16')
        end
      end
    end

    context 'with distance_unit parameter' do
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:track) do
        create(:track,
               user: user,
               start_at: day + 9.hours,
               end_at: day + 10.hours,
               distance: 16_093,
               duration: 3600,
               dominant_mode: :driving)
      end

      it 'converts distance to miles when distance_unit is mi' do
        result = described_class.new(
          user,
          start_at: day.iso8601,
          end_at: (day + 1.day).iso8601,
          distance_unit: 'mi'
        ).call

        journey = result.first[:entries].first
        expect(journey[:distance_unit]).to eq('mi')
        expect(journey[:distance]).to eq(10.0) # 16093m ≈ 10.0 mi
        expect(journey[:speed_unit]).to eq('mph')

        summary = result.first[:summary]
        expect(summary[:distance_unit]).to eq('mi')
        expect(summary[:total_distance]).to eq(10.0)
      end

      it 'defaults to km' do
        result = described_class.new(
          user,
          start_at: day.iso8601,
          end_at: (day + 1.day).iso8601
        ).call

        journey = result.first[:entries].first
        expect(journey[:distance_unit]).to eq('km')
        expect(journey[:distance]).to eq(16.1) # 16093m ≈ 16.1 km
        expect(journey[:speed_unit]).to eq('km/h')
      end
    end

    context 'does not leak data between users' do
      let(:other_user) { create(:user) }
      let(:day) { Time.zone.parse('2025-01-15 00:00:00') }

      let!(:own_visit) do
        create(:visit,
               user: user,
               place: place,
               name: 'My Visit',
               started_at: day + 10.hours,
               ended_at: day + 12.hours,
               duration: 120) # minutes
      end

      let!(:other_visit) do
        create(:visit,
               user: other_user,
               place: place,
               name: 'Other Visit',
               started_at: day + 10.hours,
               ended_at: day + 12.hours,
               duration: 120) # minutes
      end

      subject do
        described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601).call
      end

      it 'only returns data for the specified user' do
        entries = subject.first[:entries]
        expect(entries.length).to eq(1)
        expect(entries.first[:name]).to eq('My Visit')
      end
    end

    context 'when start_at or end_at is nil' do
      it 'returns empty array when start_at is nil' do
        result = described_class.new(user, start_at: nil, end_at: '2025-01-16T00:00:00Z').call
        expect(result).to eq([])
      end

      it 'returns empty array when end_at is nil' do
        result = described_class.new(user, start_at: '2025-01-15T00:00:00Z', end_at: nil).call
        expect(result).to eq([])
      end

      it 'returns empty array when both are nil' do
        result = described_class.new(user, start_at: nil, end_at: nil).call
        expect(result).to eq([])
      end
    end
  end

  describe '#build_visit_entry suggested_places injection' do
    let(:day) { Time.zone.parse('2025-02-10 00:00:00') }
    let(:place_main)   { create(:place, name: 'Blue Bottle', latitude: 37.78, longitude: -122.41) }
    let(:place_other)  { create(:place, name: 'Sightglass',  latitude: 37.78, longitude: -122.41) }
    let(:place_dupe)   { create(:place, name: 'Blue Bottle', latitude: 37.78, longitude: -122.41) }

    let(:visit) do
      create(:visit,
             user: user,
             place: place_main,
             name: 'Blue Bottle',
             started_at: day + 9.hours,
             ended_at: day + 10.hours,
             duration: 60,
             status: :suggested)
    end

    let(:assembler) do
      described_class.new(user, start_at: day.iso8601, end_at: (day + 1.day).iso8601)
    end

    it 'puts visit.place at index 0 when not in suggested_places' do
      visit.suggested_places << place_other

      entry = assembler.build_visit_entry(visit.reload)

      expect(entry[:suggested_places].first[:id]).to eq(place_main.id)
      expect(entry[:suggested_places].first[:name]).to eq('Blue Bottle')
      expect(entry[:suggested_places].map { |p| p[:id] }).to include(place_other.id)
    end

    it 'puts visit.place at index 0 when already in suggested_places (no duplicates)' do
      visit.suggested_places << place_main
      visit.suggested_places << place_other

      entry = assembler.build_visit_entry(visit.reload)

      ids = entry[:suggested_places].map { |p| p[:id] }
      expect(ids.first).to eq(place_main.id)
      expect(ids.count(place_main.id)).to eq(1)
    end

    it 'keeps visit.place when a different suggested_place shares the same normalized name' do
      visit.suggested_places << place_dupe

      entry = assembler.build_visit_entry(visit.reload)

      expect(entry[:suggested_places].first[:id]).to eq(place_main.id)
      expect(entry[:suggested_places].map { |p| p[:id] }).not_to include(place_dupe.id)
    end

    it 'falls back to current behavior when visit.place is nil' do
      visit.update!(place: nil, name: 'Unknown')
      visit.suggested_places << place_other

      entry = assembler.build_visit_entry(visit.reload)

      expect(entry[:suggested_places].map { |p| p[:id] }).to eq([place_other.id])
    end
  end
end
