# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::CalculateMonth do
  describe '#call' do
    subject(:calculate_digest) { described_class.new(user.id, year, month).call }

    let(:user) { create(:user) }
    let(:year) { 2024 }
    let(:month) { 5 }

    context 'when the user has no stat for the period' do
      it 'returns nil and does not create a digest' do
        expect { calculate_digest }.not_to(change { Users::Digest.count })
        expect(calculate_digest).to be_nil
      end
    end

    context 'when the user has a stat for the period' do
      let!(:stat) do
        create(:stat,
               user: user, year: year, month: month, distance: 12_345,
               toponyms: [
                 { 'country' => 'Spain', 'cities' => [{ 'city' => 'Madrid', 'stayed_for' => 600 }] }
               ])
      end

      it 'creates a monthly digest record' do
        expect { calculate_digest }.to change { Users::Digest.count }.by(1)
      end

      it 'persists the stat distance and period type' do
        digest = calculate_digest

        expect(digest.distance).to eq(12_345)
        expect(digest.period_type).to eq('monthly')
        expect(digest.year).to eq(year)
        expect(digest.month).to eq(month)
      end

      it 'aggregates city time from the stat toponyms' do
        digest = calculate_digest

        cities = digest.time_spent_by_location['cities']
        expect(cities).to include('name' => 'Madrid', 'minutes' => 600)
      end
    end

    context 'when the user is on the Lite cloud plan' do
      let(:user) { create(:user, :lite_plan) }
      let(:year) { Time.current.year }
      let(:month) { Time.current.month }

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      let!(:in_window_stat) do
        create(:stat, user: user, year: year, month: month, distance: 5_000)
      end

      let!(:older_than_window_stat) do
        create(:stat, user: user, year: year - 2, month: 1, distance: 999_999)
      end

      it 'reflects only scoped (12-month window) totals in all_time_stats.total_distance' do
        digest = described_class.new(user.id, year, month).call

        expect(digest.all_time_stats['total_distance']).to eq('5000')
      end
    end

    describe 'user-timezone aware month boundaries' do
      let(:auckland) { 'Pacific/Auckland' }

      before do
        user.settings = (user.settings || {}).merge('timezone' => auckland)
        user.save!

        create(:stat, user: user, year: 2024, month: 5, distance: 100,
                      toponyms: [{ 'country' => 'New Zealand',
                                   'cities' => [{ 'city' => 'Auckland', 'stayed_for' => 60 }] }])
      end

      it "groups a UTC-late-May 31 point into the user's local-day grouping for May" do
        utc_in_may = Time.zone.parse('2024-05-31 06:00:00 UTC')
        create(:point, user: user, country_name: 'New Zealand',
                       timestamp: utc_in_may.to_i,
                       latitude: -36.85, longitude: 174.76)

        digest = described_class.new(user.id, 2024, 5).call

        expect(digest).to be_present
        countries = digest.time_spent_by_location['countries']
        expect(countries).to include('name' => 'New Zealand', 'minutes' => 1_440)
      end

      it "uses the user's timezone (not the server zone) when grouping points by date" do
        june_in_user_tz = Time.zone.parse('2024-05-31 14:00:00 UTC')
        create(:point, user: user, country_name: 'New Zealand',
                       timestamp: june_in_user_tz.to_i,
                       latitude: -36.85, longitude: 174.76)

        utc_in_may = Time.zone.parse('2024-05-30 02:00:00 UTC')
        create(:point, user: user, country_name: 'New Zealand',
                       timestamp: utc_in_may.to_i,
                       latitude: -36.85, longitude: 174.76)

        digest = described_class.new(user.id, 2024, 5).call
        countries = digest.time_spent_by_location['countries']
        nz = countries.find { |c| c['name'] == 'New Zealand' }

        expect(nz['minutes']).to eq(1_440)
      end
    end
  end
end
