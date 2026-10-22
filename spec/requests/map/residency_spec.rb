# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map::Residency', type: :request do
  describe 'GET /map/residency' do
    context 'when user is signed in' do
      let(:user) { create(:user) }

      before do
        sign_in user
        create(:stat, user:, year: 2026, month: 3, distance: 1000)
        create(:point, user:, country_name: 'Germany', timestamp: Time.zone.local(2026, 3, 4, 12).to_i)
        create(:point, user:, country_name: 'Czechia', timestamp: Time.zone.local(2026, 3, 6, 12).to_i)
      end

      it 'renders the year calendar and the country timeline' do
        get map_residency_path(year: 2026)

        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css('[data-testid="year-calendar"]')).to be_present
        expect(doc.at_css('[data-testid="country-ribbon"]')).to be_present
      end

      it 'counts the days for the requested year' do
        get map_residency_path(year: 2026)

        expect(response.body).to include('Germany')
        expect(response.body).to include('Czechia')
      end

      it 'uses distinct theme-independent colors for countries' do
        %w[France Spain Italy Netherlands Poland Austria].each_with_index do |country_name, index|
          create(:point, user:, country_name:, timestamp: Time.zone.local(2026, 4, index + 1, 12).to_i)
        end

        get map_residency_path(year: 2026)

        colors = Nokogiri::HTML(response.body).css('[data-testid="year-calendar-countries"] button span:first-child')
                         .map { _1['style'][/#\h{6}/] }
        expect(colors.size).to eq(8)
        expect(colors.uniq.size).to eq(8)
      end

      it 'takes the year from the page instead of offering its own selector' do
        get map_residency_path(year: 2026)

        expect(response.body).not_to include('data-action="change->residency#changeYear"')
      end
    end

    context 'when user is not signed in' do
      it 'redirects to the sign in page' do
        get map_residency_path(year: 2026)

        expect(response).to have_http_status(302)
      end
    end
  end
end
