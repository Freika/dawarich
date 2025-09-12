# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared::Stats', type: :request do
  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  context 'public sharing' do
    let(:user) { create(:user) }
    let(:stat) { create(:stat, :with_sharing_enabled, user:, year: 2024, month: 6) }

    describe 'GET /shared/stats/:uuid' do
      context 'with valid sharing UUID' do
        before do
          # Create some test points for data bounds calculation
          create_list(:point, 5, user:, timestamp: Time.new(2024, 6, 15).to_i)
        end

        it 'renders the public month view' do
          get shared_stat_url(stat.sharing_uuid)

          expect(response).to have_http_status(:success)
          expect(response.body).to include('Monthly Digest')
          expect(response.body).to include('June 2024')
        end

        it 'includes required content in response' do
          get shared_stat_url(stat.sharing_uuid)

          expect(response.body).to include('June 2024')
          expect(response.body).to include('Monthly Digest')
          expect(response.body).to include('data-public-stat-map-uuid-value')
          expect(response.body).to include(stat.sharing_uuid)
        end
      end

      context 'with invalid sharing UUID' do
        it 'redirects to root with alert' do
          get shared_stat_url('invalid-uuid')

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq('Shared stats not found or no longer available')
        end
      end

      context 'with expired sharing' do
        let(:stat) { create(:stat, :with_sharing_expired, user:, year: 2024, month: 6) }

        it 'redirects to root with alert' do
          get shared_stat_url(stat.sharing_uuid)

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq('Shared stats not found or no longer available')
        end
      end

      context 'with disabled sharing' do
        let(:stat) { create(:stat, :with_sharing_disabled, user:, year: 2024, month: 6) }

        it 'redirects to root with alert' do
          get shared_stat_url(stat.sharing_uuid)

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq('Shared stats not found or no longer available')
        end
      end

      context 'when stat has no points' do
        it 'renders successfully' do
          get shared_stat_url(stat.sharing_uuid)

          expect(response).to have_http_status(:success)
          expect(response.body).to include('Monthly Digest')
        end
      end
    end

    describe 'PATCH /stats/:year/:month/sharing' do
      context 'when user is signed in' do
        let!(:stat_to_share) { create(:stat, user:, year: 2024, month: 6) }

        before { sign_in user }

        context 'enabling sharing' do
          it 'enables sharing and returns success' do
            patch sharing_stats_path(year: 2024, month: 6),
                  params: { enabled: '1' },
                  as: :json

            expect(response).to have_http_status(:success)

            json_response = JSON.parse(response.body)
            expect(json_response['success']).to be(true)
            expect(json_response['sharing_url']).to be_present
            expect(json_response['message']).to eq('Sharing enabled successfully')

            stat_to_share.reload
            expect(stat_to_share.sharing_enabled?).to be(true)
            expect(stat_to_share.sharing_uuid).to be_present
          end

          it 'sets custom expiration when provided' do
            patch sharing_stats_path(year: 2024, month: 6),
                  params: { enabled: '1', expiration: '1_week' },
                  as: :json

            expect(response).to have_http_status(:success)
            stat_to_share.reload
            expect(stat_to_share.sharing_enabled?).to be(true)
          end
        end

        context 'disabling sharing' do
          let!(:enabled_stat) { create(:stat, :with_sharing_enabled, user:, year: 2024, month: 7) }

          it 'disables sharing and returns success' do
            patch sharing_stats_path(year: 2024, month: 7),
                  params: { enabled: '0' },
                  as: :json

            expect(response).to have_http_status(:success)

            json_response = JSON.parse(response.body)
            expect(json_response['success']).to be(true)
            expect(json_response['message']).to eq('Sharing disabled successfully')

            enabled_stat.reload
            expect(enabled_stat.sharing_enabled?).to be(false)
          end
        end

        context 'when stat does not exist' do
          it 'returns not found' do
            patch sharing_stats_path(year: 2024, month: 12),
                  params: { enabled: '1' },
                  as: :json

            expect(response).to have_http_status(:not_found)
          end
        end
      end

      context 'when user is not signed in' do
        it 'returns unauthorized' do
          patch sharing_stats_path(year: 2024, month: 6),
                params: { enabled: '1' },
                as: :json

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end
end
