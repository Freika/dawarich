# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::CalculateWeek do
  describe '#call' do
    let(:user) { create(:user) }
    let(:start_date) { Date.new(2026, 7, 20) }
    let(:end_date) { Date.new(2026, 7, 26) }

    # Leipzig and a point ~7 km east of it.
    let(:leipzig) { [51.3402, 12.3712] }
    let(:leipzig_east) { [51.3402, 12.4712] }

    def run_calculation(from: start_date, to: end_date)
      described_class.new(user.id, from, to).call
    end

    def create_point(at:, coordinates: leipzig, city: 'Leipzig', country: 'Germany')
      create(
        :point,
        user: user,
        timestamp: at.to_i,
        latitude: coordinates[0],
        longitude: coordinates[1],
        lonlat: "POINT(#{coordinates[1]} #{coordinates[0]})",
        city: city,
        country: country
      )
    end

    context 'when the user has points inside the range' do
      before do
        create_point(at: Time.utc(2026, 7, 22, 9, 0))
        create_point(at: Time.utc(2026, 7, 22, 10, 0), coordinates: leipzig_east)
      end

      it 'persists exactly one weekly digest' do
        expect { run_calculation }.to change { Users::Digest.weekly.count }.by(1)
      end

      it 'records a non-zero distance' do
        digest = run_calculation

        expect(digest.distance).to be > 0
      end

      it 'keys the digest on the ISO week of the range end' do
        digest = run_calculation

        expect(digest.period_type).to eq('weekly')
        expect(digest.year).to eq(end_date.cwyear)
        expect(digest.week).to eq(end_date.cweek)
        expect(digest.month).to be_nil
      end

      it 'does not require a stat row to exist' do
        expect(Stat.count).to eq(0)
        expect { run_calculation }.not_to raise_error
        expect(Stat.count).to eq(0)
      end

      it 'leaves the month-only and year-only fields at their defaults' do
        digest = run_calculation

        expect(digest.monthly_distances).to eq({})
        expect(digest.first_time_visits).to eq({})
        expect(digest.year_over_year).to eq({})
      end
    end

    context 'when the user stayed long enough in a city' do
      before do
        create_point(at: Time.utc(2026, 7, 22, 9, 0))
        create_point(at: Time.utc(2026, 7, 22, 10, 0), coordinates: leipzig_east)
        create_point(at: Time.utc(2026, 7, 22, 11, 0))
      end

      it 'records the country and city in toponyms' do
        digest = run_calculation

        countries = digest.toponyms.map { |toponym| toponym['country'] }
        cities = digest.toponyms.flat_map { |toponym| toponym['cities'].map { |city| city['city'] } }

        expect(countries).to include('Germany')
        expect(cities).to include('Leipzig')
      end

      it 'records time spent by location' do
        digest = run_calculation

        country_names = digest.time_spent_by_location['countries'].map { |entry| entry['name'] }

        expect(country_names).to include('Germany')
        expect(digest.time_spent_by_location['total_country_minutes']).to be > 0
      end
    end

    context 'when the user has no points in the range' do
      it 'persists a digest with zero distance instead of raising' do
        digest = nil

        expect { digest = run_calculation }.to change { Users::Digest.weekly.count }.by(1)
        expect(digest.distance).to eq(0)
        expect(digest.toponyms).to eq([])
      end
    end

    context 'when points fall outside the range' do
      before do
        create_point(at: Time.utc(2026, 7, 10, 9, 0))
        create_point(at: Time.utc(2026, 7, 10, 10, 0), coordinates: leipzig_east)
      end

      it 'excludes them from the distance' do
        digest = run_calculation

        expect(digest.distance).to eq(0)
      end
    end

    context 'when run twice for the same user and range' do
      before do
        create_point(at: Time.utc(2026, 7, 22, 9, 0))
        create_point(at: Time.utc(2026, 7, 22, 10, 0), coordinates: leipzig_east)
      end

      it 'updates the existing digest rather than duplicating it' do
        first = run_calculation

        expect { run_calculation }.not_to(change { Users::Digest.weekly.count })
        expect(Users::Digest.weekly.pluck(:id)).to eq([first.id])
      end

      it 'reflects points added between runs' do
        first_distance = run_calculation.distance
        create_point(at: Time.utc(2026, 7, 23, 9, 0))
        create_point(at: Time.utc(2026, 7, 23, 10, 0), coordinates: leipzig_east)

        expect(run_calculation.distance).to be > first_distance
      end
    end

    context 'when the range spans a month boundary' do
      let(:start_date) { Date.new(2026, 7, 29) }
      let(:end_date) { Date.new(2026, 8, 4) }

      before do
        create_point(at: Time.utc(2026, 7, 30, 9, 0))
        create_point(at: Time.utc(2026, 7, 30, 10, 0), coordinates: leipzig_east)
        create_point(at: Time.utc(2026, 8, 2, 9, 0))
        create_point(at: Time.utc(2026, 8, 2, 10, 0), coordinates: leipzig_east)
      end

      it 'counts distance from both months' do
        single_day = described_class.new(user.id, Date.new(2026, 7, 30), Date.new(2026, 7, 30)).call.distance
        Users::Digest.delete_all

        expect(run_calculation.distance).to be > single_day
      end
    end
  end
end
