# frozen_string_literal: true

require 'rails_helper'

# Regression guard for the Lite partial-window digest scope-mixing bug.
#
# A cloud-Lite user whose 12-month data window (data_window_start) cuts into the
# middle of an accepted year must not receive a digest whose per-year fields
# contradict each other. Before the fix, SeasonalityCalculator read unscoped
# `user.stats` (full year) while monthly_distances/toponyms used scoped
# `user.scoped_stats` (in-window subset), and fetch_daily_country_stats read raw
# `points` for the full year without the data_window_start filter. The same
# served record therefore claimed non-zero seasonality for seasons whose months
# were all zero, and named countries the toponym list omitted.
#
# Frozen at 2026-09-06 -> Lite 12-month window (data_window_start) lands at
# 2025-09, so months 1-8 of the boundary year 2025 are out of window.
RSpec.describe 'Lite partial-window digest scope consistency', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :lite_plan) }

  around { |example| travel_to(Time.utc(2026, 9, 6, 12)) { example.run } }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    (1..6).each do |month|
      create(:stat, user: user, year: 2025, month: month, distance: 1_000, toponyms: [
               { 'country' => 'France', 'cities' => [{ 'city' => 'Paris', 'stayed_for' => 1440 }] }
             ])
    end
    (7..12).each do |month|
      create(:stat, user: user, year: 2025, month: month, distance: 1_000, toponyms: [
               { 'country' => 'Russia', 'cities' => [{ 'city' => 'Moscow', 'stayed_for' => 1440 }] }
             ])
    end

    create(:point, user: user, timestamp: Time.utc(2025, 1, 1, 10, 0).to_i, country_name: 'France', city: 'Paris')
    create(:point, user: user, timestamp: Time.utc(2025, 1, 2, 10, 0).to_i, country_name: 'France', city: 'Paris')
    create(:point, user: user, timestamp: Time.utc(2025, 12, 1, 10, 0).to_i, country_name: 'Russia', city: 'Moscow')
    create(:point, user: user, timestamp: Time.utc(2025, 12, 2, 10, 0).to_i, country_name: 'Russia', city: 'Moscow')
  end

  describe 'Users::Digests::CalculateYear' do
    let(:digest) { Users::Digests::CalculateYear.new(user.id, 2025).call }

    it 'scopes distance to the in-window subset' do
      expect(digest.distance).to eq(4_000)
    end

    it 'scopes toponyms to the in-window subset' do
      expect(digest.toponyms.map { |t| t['country'] }).to eq(['Russia'])
    end

    it 'zeroes out-of-window months in monthly_distances' do
      expect(digest.monthly_distances['3']).to eq('0')
      expect(digest.monthly_distances['8']).to eq('0')
      expect(digest.monthly_distances['9']).to eq('1000')
      expect(digest.monthly_distances['12']).to eq('1000')
    end

    context 'with season-vs-month consistency (coupling 1)' do
      it 'does not report seasonality for seasons whose months are all zero' do
        seasonality = digest.travel_patterns['seasonality']

        expect(digest.monthly_distances['3']).to eq('0')
        expect(digest.monthly_distances['4']).to eq('0')
        expect(digest.monthly_distances['5']).to eq('0')
        expect(seasonality['spring']).to eq(0)

        expect(digest.monthly_distances['6']).to eq('0')
        expect(digest.monthly_distances['7']).to eq('0')
        expect(digest.monthly_distances['8']).to eq('0')
        expect(seasonality['summer']).to eq(0)
      end

      it 'reports seasonality only for in-window seasons with non-zero distance' do
        seasonality = digest.travel_patterns['seasonality']

        expect(seasonality['fall']).to be > 0
        expect(seasonality['winter']).to be > 0
        expect(seasonality.values.sum).to eq(100)
      end

      it 'satisfies the season-vs-month invariant for every season' do
        seasonality = digest.travel_patterns['seasonality']

        season_months = {
          'winter' => %w[12 1 2],
          'spring' => %w[3 4 5],
          'summer' => %w[6 7 8],
          'fall'   => %w[9 10 11]
        }

        season_months.each do |season, months|
          month_distances = months.map { |m| digest.monthly_distances[m].to_f }

          if seasonality[season] > 0
            expect(month_distances).to include(be > 0), "#{season} > 0 but all its months are 0"
          else
            expect(month_distances).to all(be_zero), "#{season} == 0 but a month of it is > 0"
          end
        end
      end
    end

    context 'with country set consistency (coupling 2)' do
      it 'scopes time_spent_by_location countries to the in-window subset' do
        expect(digest.time_spent_by_location['countries'].map { |c| c['name'] }).to eq(['Russia'])
      end

      it 'does not name a country the toponym list omits' do
        toponym_countries = digest.toponyms.map { |t| t['country'] }
        time_spent_countries = digest.time_spent_by_location['countries'].map { |c| c['name'] }

        expect(toponym_countries).not_to include('France')
        expect(time_spent_countries).not_to include('France')
        expect(time_spent_countries).to all(be_in(toponym_countries))
      end
    end
  end

  describe 'end-to-end via the API' do
    let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

    before do
      allow_any_instance_of(Stats::CalculateMonth).to receive(:call).and_return(true)
      allow(Users::Digests::Yearly::EmailSendingJob).to receive(:perform_later).and_return(true)
    end

    it 'serves a self-consistent digest through the production path' do
      expect do
        post api_v1_digests_path, params: { year: 2025 }, headers: headers
      end.to have_enqueued_job(Users::Digests::Yearly::CalculatingJob).with(user.id, 2025)
      expect(response).to have_http_status(:accepted)

      perform_enqueued_jobs

      get api_v1_digest_url(year: 2025), headers: headers
      expect(response).to have_http_status(:ok)

      json = response.parsed_body

      expect(json['distance']['meters']).to eq(4_000)
      expect(json['toponyms']['countries'].map { |c| c['country'] }).to eq(['Russia'])
      expect(json['monthlyDistances']['march']).to eq(0.0)
      expect(json['monthlyDistances']['august']).to eq(0.0)

      seasonality = json['travelPatterns']['seasonality']
      expect(seasonality['spring']).to eq(0)
      expect(seasonality['summer']).to eq(0)
      expect(seasonality['fall']).to be > 0

      time_spent_countries = json['timeSpentByLocation']['countries'].map { |c| c['name'] }
      toponym_countries = json['toponyms']['countries'].map { |c| c['country'] }
      expect(time_spent_countries).not_to include('France')
      expect(time_spent_countries).to all(be_in(toponym_countries))
    end
  end
end
