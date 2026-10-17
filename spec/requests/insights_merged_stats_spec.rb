# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Insights as the single stats page', type: :request do
  let(:user) { create(:user) }

  def doc = Nokogiri::HTML(response.body)

  before { sign_in user }

  describe 'old stats addresses' do
    it 'sends /stats to the all-time view' do
      get stats_path

      expect(response).to redirect_to(insights_path(year: 'all'))
      expect(response).to have_http_status(:found)
    end

    it 'sends /stats/:year to that year' do
      get '/stats/2025'

      expect(response).to redirect_to(insights_path(year: 2025))
    end

    it 'keeps the month page where it is' do
      create(:stat, user:, year: 2024, month: 6)

      get '/stats/2024/6'

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("a.btn[href='#{insights_path(year: 2024)}']")).to be_present
    end

    it 'returns to the matching view after recalculating' do
      put update_all_stats_path
      expect(response).to redirect_to(insights_path(year: 'all'))

      put update_year_month_stats_path(year: '2024', month: '1')
      expect(response).to redirect_to(insights_path(year: '2024'))
    end
  end

  describe 'all-time view' do
    before do
      create(:stat, user:, year: 2024, month: 6, distance: 12_000)
      create(:stat, user:, year: 2023, month: 3, distance: 8_000)
    end

    it 'lists every year as a card that opens that year' do
      get insights_path(year: 'all')

      cards = doc.css('[data-testid="insights-year-card"]')
      expect(cards.map { _1.at_css('a')['href'] }).to eq([insights_path(year: 2024), insights_path(year: 2023)])
    end

    it 'offers recalculating every year' do
      get insights_path(year: 'all')

      expect(doc.css("a[href='#{update_all_stats_path}']")).to be_present
    end

    it 'keeps the tracked points and the visited countries and cities lists' do
      configure_instance_geocoding

      get insights_path(year: 'all')

      expect(response.body).to include(I18n.t('stats.index.geopoints_tracked'))
      expect(doc.css('dialog#countries_visited')).to be_present
      expect(doc.css('dialog#cities_visited')).to be_present
    end

    it 'does not show the month grid of a single year' do
      get insights_path(year: 'all')

      expect(doc.css("a[href='#{month_stats_path(year: 2024, month: 6)}']")).to be_empty
    end
  end

  describe 'year view' do
    before { create(:stat, user:, year: 2024, month: 6, distance: 12_000) }

    it 'shows the months of the year, each opening its month page' do
      get insights_path(year: 2024)

      expect(doc.css("a[href='#{month_stats_path(year: 2024, month: 6)}']")).to be_present
    end

    it 'does not list the year cards' do
      get insights_path(year: 2024)

      expect(doc.css("a[href='#{update_all_stats_path}']")).to be_empty
    end

    it 'marks the chosen period' do
      get insights_path(year: 2024)

      active = doc.css('[data-testid="insights-period"] [aria-current="page"]').map { _1.text.strip }
      expect(active).to eq(['2024'])
    end
  end

  describe 'Lite plan on Cloud' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update!(plan: :lite)
      create(:stat, user:, year: Time.current.year, month: Time.current.month)
      create(:stat, user:, year: 2019, month: 5)
    end

    it 'shows years outside the data window as locked cards' do
      get insights_path(year: 'all')

      expect(response.body).to include(I18n.t('stats.locked_year_card.available_on_pro'))
      card_links = doc.css('[data-testid="insights-year-card"] a').map { _1['href'] }
      expect(card_links).to include(insights_path(year: Time.current.year))
      expect(card_links).not_to include(insights_path(year: 2019))
    end

    it 'shows no months for a locked year' do
      get insights_path(year: 2019)

      expect(doc.css("a[href^='/stats/2019/']")).to be_empty
    end
  end

  describe 'navigation' do
    it 'links to Insights and no longer to Stats' do
      get insights_path

      hrefs = doc.css('nav a, .navbar a').map { _1['href'] }
      expect(hrefs).to include(insights_url)
      expect(hrefs).not_to include(stats_url)
    end
  end
end
