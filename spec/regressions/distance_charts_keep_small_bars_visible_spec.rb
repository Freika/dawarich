# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Distance charts keep small bars visible beside an outlier', type: :request do
  let(:user) { create(:user, settings: { 'distance_unit' => 'km' }) }

  # Chartkick renders `new Chartkick["ColumnChart"](id, data, options)`; take the chart
  # whose data includes the outlier, so the shape of other charts on the page does not matter.
  def column_chart_with(body, value)
    scripts = Nokogiri::HTML(body).css('script').map(&:text)
    calls = scripts.filter_map { |text| text[/new Chartkick\["ColumnChart"\]\((.*?)\);/m, 1] }
    charts = calls.map { |arguments| JSON.parse("[#{arguments}]") }
    charts.find { |_, data, _| data.any? { |_, bar_value| bar_value == value } } or
      raise "no column chart with a #{value} bar among #{charts.size}"
  end

  def expect_small_bars_visible(chart, small_value:)
    _, data, options = chart
    values = data.map(&:last)

    expect(values).to include(small_value)
    expect(options.dig('library', 'datasets', 'bar', 'minBarLength')).to be >= 5
    # A day or month without movement, or with less than half a unit, has no
    # bar, not a minimum-height one labelled 0.
    expect(values).not_to include(0)
  end

  describe 'Daily Activity' do
    let!(:stat) do
      create(:stat, :with_sharing_enabled, user:, year: 2026, month: 6, toponyms: [], distance: 10_150_000,
                                           daily_distance: [[1, 150_000], [2, 10_000_000], [3, 0], [4, 300]])
    end

    it 'gives a 150 km day a visible bar next to a 10,000 km day on the month page' do
      sign_in user
      get month_stats_path(year: stat.year, month: stat.month)

      expect(response).to have_http_status(:ok)
      expect_small_bars_visible(column_chart_with(response.body, 10_000), small_value: 150)
    end

    it 'does the same on the shared month page' do
      get shared_stat_url(stat.sharing_uuid)

      expect(response).to have_http_status(:ok)
      expect_small_bars_visible(column_chart_with(response.body, 10_000), small_value: 150)
    end
  end

  describe 'Year by month' do
    let!(:digest) do
      create(:users_digest, :with_sharing_enabled, user:, year: 2025,
                                                   monthly_distances: { '1' => '150000', '2' => '10000000',
                                                                        '3' => '0', '4' => '300' })
    end

    it 'gives a 150 km month a visible bar next to a 10,000 km month on the digest page' do
      sign_in user
      get users_digest_path(year: digest.year)

      expect(response).to have_http_status(:ok)
      expect_small_bars_visible(column_chart_with(response.body, 10_000), small_value: 150)
    end

    it 'does the same on the shared digest page' do
      get shared_users_digest_url(digest.sharing_uuid)

      expect(response).to have_http_status(:ok)
      expect_small_bars_visible(column_chart_with(response.body, 10_000), small_value: 150)
    end
  end
end
