# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared::Digests', type: :request do
  context 'public sharing' do
    let(:user) { create(:user) }
    let(:digest) { create(:users_digest, :with_sharing_enabled, user:, year: 2024) }

    describe 'GET /shared/digest/:uuid' do
      context 'with valid sharing UUID' do
        it 'renders the public year view' do
          get shared_users_digest_url(digest.sharing_uuid)

          expect(response).to have_http_status(:success)
          expect(response.body).to include('Year in Review')
          expect(response.body).to include('2024')
        end

        it 'includes required content in response' do
          get shared_users_digest_url(digest.sharing_uuid)

          expect(response.body).to include('2024')
          expect(response.body).to include('Distance traveled')
          expect(response.body).to include('Countries visited')
        end
      end

      context 'with invalid sharing UUID' do
        it 'redirects to root with alert' do
          get shared_users_digest_url('invalid-uuid')

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq('Shared digest not found or no longer available')
        end
      end

      context 'with expired sharing' do
        let(:digest) { create(:users_digest, :with_sharing_expired, user:, year: 2024) }

        it 'redirects to root with alert' do
          get shared_users_digest_url(digest.sharing_uuid)

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq('Shared digest not found or no longer available')
        end
      end

      context 'with disabled sharing' do
        let(:digest) { create(:users_digest, :with_sharing_disabled, user:, year: 2024) }

        it 'redirects to root with alert' do
          get shared_users_digest_url(digest.sharing_uuid)

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq('Shared digest not found or no longer available')
        end
      end
    end

    describe 'PATCH /digests/:year/sharing' do
      context 'when user is signed in' do
        let!(:digest_to_share) { create(:users_digest, user:, year: 2024) }

        before { sign_in user }

        context 'enabling sharing' do
          it 'enables sharing and returns success' do
            patch sharing_users_digest_path(year: 2024),
                  params: { enabled: '1' },
                  as: :json

            expect(response).to have_http_status(:success)

            json_response = JSON.parse(response.body)
            expect(json_response['success']).to be(true)
            expect(json_response['sharing_url']).to be_present
            expect(json_response['message']).to eq('Sharing enabled successfully')

            digest_to_share.reload
            expect(digest_to_share.sharing_enabled?).to be(true)
            expect(digest_to_share.sharing_uuid).to be_present
          end

          it 'sets custom expiration when provided' do
            patch sharing_users_digest_path(year: 2024),
                  params: { enabled: '1', expiration: '12h' },
                  as: :json

            expect(response).to have_http_status(:success)
            digest_to_share.reload
            expect(digest_to_share.sharing_enabled?).to be(true)
          end
        end

        context 'disabling sharing' do
          let!(:enabled_digest) { create(:users_digest, :with_sharing_enabled, user:, year: 2023) }

          it 'disables sharing and returns success' do
            patch sharing_users_digest_path(year: 2023),
                  params: { enabled: '0' },
                  as: :json

            expect(response).to have_http_status(:success)

            json_response = JSON.parse(response.body)
            expect(json_response['success']).to be(true)
            expect(json_response['message']).to eq('Sharing disabled successfully')

            enabled_digest.reload
            expect(enabled_digest.sharing_enabled?).to be(false)
          end
        end

        context 'when digest does not exist' do
          it 'returns not found' do
            patch sharing_users_digest_path(year: 2020),
                  params: { enabled: '1' },
                  as: :json

            expect(response).to have_http_status(:not_found)
          end
        end
      end

      context 'when user is not signed in' do
        it 'returns unauthorized' do
          patch sharing_users_digest_path(year: 2024),
                params: { enabled: '1' },
                as: :json

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end
end
