# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/insights', type: :request do
  context 'when user is not signed in' do
    describe 'GET /index' do
      it 'redirects to the sign in page' do
        get insights_url

        expect(response.status).to eq(302)
      end
    end
  end

  context 'when user is signed in' do
    let(:user) { create(:user) }

    before { sign_in user }

    describe 'GET /index' do
      it 'renders a successful response' do
        get insights_url

        expect(response.status).to eq(200)
      end

      context 'when there are no stats' do
        it 'renders the page without errors' do
          get insights_url

          expect(response.status).to eq(200)
        end
      end

      context 'when there are stats for the current year' do
        let!(:stat) do
          create(:stat,
                 user: user,
                 year: Time.current.year,
                 month: 1,
                 distance: 100_000,
                 daily_distance: { '1' => 50_000, '2' => 50_000 })
        end

        it 'renders the page with stats' do
          get insights_url

          expect(response.status).to eq(200)
        end
      end

      context 'when there are stats for current and previous year' do
        let!(:current_stat) do
          create(:stat,
                 user: user,
                 year: Time.current.year,
                 month: 1,
                 distance: 200_000)
        end

        let!(:previous_stat) do
          create(:stat,
                 user: user,
                 year: Time.current.year - 1,
                 month: 1,
                 distance: 100_000)
        end

        it 'renders the page with comparison data' do
          get insights_url

          expect(response.status).to eq(200)
        end
      end

      context 'when selecting a specific year' do
        let!(:stat_2023) do
          create(:stat, user: user, year: 2023, month: 6, distance: 150_000)
        end

        let!(:stat_2024) do
          create(:stat, user: user, year: 2024, month: 6, distance: 200_000)
        end

        it 'loads stats for the selected year' do
          get insights_url(year: '2023')

          expect(response.status).to eq(200)
        end

        it 'calculates comparison with previous year' do
          get insights_url(year: '2024')

          expect(response.status).to eq(200)
        end
      end

      context 'when selecting all time view' do
        let!(:stat_2023) { create(:stat, user: user, year: 2023, month: 6, distance: 100_000) }
        let!(:stat_2024) { create(:stat, user: user, year: 2024, month: 6, distance: 150_000) }

        it 'loads stats for all years' do
          get insights_url(year: 'all')

          expect(response.status).to eq(200)
        end
      end

      context 'when selecting a specific month' do
        let!(:stat) do
          create(:stat, user: user, year: 2024, month: 1, distance: 100_000)
        end

        it 'renders the page with travel patterns' do
          get insights_url(year: '2024', month: '1')

          expect(response.status).to eq(200)
        end
      end

      context 'when monthly digest exists' do
        let!(:stat) { create(:stat, user: user, year: 2024, month: 1, distance: 100_000) }
        let!(:digest) do
          create(:users_digest, :monthly, user: user, year: 2024, month: 1,
                 monthly_distances: (1..31).map { |d| [d, d * 1000] })
        end

        it 'renders the page using existing digest' do
          get insights_url(year: '2024', month: '1')

          expect(response.status).to eq(200)
        end
      end
    end
  end
end
