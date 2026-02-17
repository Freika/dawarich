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
               duration: 3600)
      end

      let!(:track1) do
        create(:track,
               user: user,
               start_at: day + 8.hours,
               end_at: day + 8.hours + 30.minutes,
               distance: 8500,
               duration: 1800,
               dominant_mode: :cycling)
      end

      let!(:visit2) do
        create(:visit,
               user: user,
               place: place2,
               name: 'Office',
               started_at: day + 8.hours + 30.minutes,
               ended_at: day + 17.hours,
               duration: 30_600)
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
        expect(journey[:avg_speed_kmh]).to be_a(Float)
        expect(journey).to have_key(:elevation_gain)
        expect(journey).to have_key(:elevation_loss)
      end

      it 'calculates summary with distance and places' do
        summary = subject.first[:summary]
        expect(summary[:total_distance_km]).to eq(8.5)
        expect(summary[:places_visited]).to eq(2)
      end

      it 'calculates time breakdown' do
        summary = subject.first[:summary]
        expect(summary[:time_moving_minutes]).to eq(30)
        expect(summary[:time_stationary_minutes]).to eq(570)
      end

      it 'provides bounding box' do
        bounds = subject.first[:bounds]
        expect(bounds).to have_key(:sw_lat)
        expect(bounds).to have_key(:sw_lng)
        expect(bounds).to have_key(:ne_lat)
        expect(bounds).to have_key(:ne_lng)
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
               duration: 7200)
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
        expect(subject.first[:summary][:total_distance_km]).to eq(0.0)
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
        expect(entries.first[:distance_km]).to eq(15.0)
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
               duration: 7200)
      end

      let!(:visit_day2) do
        create(:visit,
               user: user,
               place: place2,
               name: 'Office',
               started_at: day2 + 9.hours,
               ended_at: day2 + 17.hours,
               duration: 28_800)
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
               duration: 7200)
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
               duration: 7200)
      end

      let!(:other_visit) do
        create(:visit,
               user: other_user,
               place: place,
               name: 'Other Visit',
               started_at: day + 10.hours,
               ended_at: day + 12.hours,
               duration: 7200)
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
  end
end
