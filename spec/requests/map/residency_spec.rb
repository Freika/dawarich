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

      it 'renders a countries card and a heatmap card side by side' do
        get map_residency_path(year: 2026)

        expect(response.body).to include(I18n.t('map.residency.show.countries'))
        expect(response.body).to include(I18n.t('map.residency.show.days_per_country'))
      end

      it 'counts the days for the requested year' do
        get map_residency_path(year: 2026)

        expect(response.body).to include('Germany')
        expect(response.body).to include('Czechia')
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
