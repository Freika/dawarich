# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/stats', type: :request do
  context 'when user is not signed in' do
    describe 'GET /index' do
      it 'redirects to the sign in page' do
        get stats_url

        expect(response.status).to eq(302)
      end
    end

    describe 'GET /show' do
      it 'redirects to the sign in page' do
        get stats_url(2024)

        expect(response.status).to eq(401)
      end
    end
  end

  context 'when user is signed in' do
    let(:user) { create(:user) }

    before { sign_in user }

    describe 'GET /index' do
      it 'renders a successful response' do
        get stats_url

        expect(response.status).to eq(200)
      end
    end

    describe 'GET /show' do
      let(:stat) { create(:stat, user:, year: 2024) }

      it 'renders a successful response' do
        get stats_url(stat.year)

        expect(response.status).to eq(200)
      end
    end

    describe 'POST /update' do
      let(:stat) { create(:stat, user:, year: 2024) }

      context 'when updating a specific month' do
        it 'enqueues Stats::CalculatingJob for the given year and month' do
          put update_year_month_stats_url(year: '2024', month: '1')

          expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, '2024', '1')
        end
      end

      context 'when updating the whole year' do
        it 'enqueues Stats::CalculatingJob for each month of the year' do
          put update_year_month_stats_url(year: '2024', month: 'all')

          (1..12).each do |month|
            expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, '2024', month)
          end
        end
      end

      context 'when user is inactive' do
        before do
          user.update(status: :inactive, active_until: 1.day.ago)
        end

        it 'returns an unauthorized response' do
          put update_year_month_stats_url(year: '2024', month: '1')

          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to eq('Your account is not active.')
        end
      end
    end

    describe 'PUT /update_all' do
      let(:stat) { create(:stat, user:, year: 2024) }

      it 'enqueues Stats::CalculatingJob for each tracked year and month' do
        allow(user).to receive(:years_tracked).and_return([{ year: 2024, months: %w[Jan Feb] }])

        put update_all_stats_url

        expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2024, 1)
        expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2024, 2)
        expect(Stats::CalculatingJob).to_not have_been_enqueued.with(user.id, 2024, 3)
      end

      context 'when user is inactive' do
        before do
          user.update(status: :inactive, active_until: 1.day.ago)
        end

        it 'returns an unauthorized response' do
          put update_all_stats_url

          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to eq('Your account is not active.')
        end
      end
    end
  end
end
