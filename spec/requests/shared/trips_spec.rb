# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared::Trips', type: :request do
  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  context 'public sharing' do
    let(:user) { create(:user) }
    let(:trip) do
      create(:trip, user: user, name: 'Test Trip',
                    started_at: 1.week.ago, ended_at: Time.current)
    end

    describe 'GET /shared/trips/:trip_uuid' do
      context 'with valid sharing UUID' do
        before do
          trip.enable_sharing!(expiration: '24h', share_notes: true, share_photos: false)
          # Create some points for the trip
          create_list(:point, 5, user: user, timestamp: trip.started_at.to_i + 1.hour)
        end

        it 'renders the public trip view' do
          get shared_trip_url(trip.sharing_uuid)

          expect(response).to have_http_status(:success)
          expect(response.body).to include('Test Trip')
        end

        it 'includes required content in response' do
          get shared_trip_url(trip.sharing_uuid)

          expect(response.body).to include('Test Trip')
          expect(response.body).to include('Trip Route')
          expect(response.body).to include('data-controller="public-trip-map"')
          expect(response.body).to include(trip.sharing_uuid)
        end

        it 'displays notes when share_notes is true' do
          trip.update(notes: 'This is a test trip')
          get shared_trip_url(trip.sharing_uuid)

          expect(response.body).to include('About This Trip')
          expect(response.body).to include('This is a test trip')
        end

        it 'does not display notes when share_notes is false' do
          trip.disable_sharing!
          trip.enable_sharing!(expiration: '24h', share_notes: false)
          trip.update(notes: 'This is a test trip')
          get shared_trip_url(trip.sharing_uuid)

          expect(response.body).not_to include('About This Trip')
        end
      end

      context 'with invalid sharing UUID' do
        it 'redirects to root with alert' do
          get shared_trip_url('invalid-uuid')

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq('Shared trip not found or no longer available')
        end
      end

      context 'with expired sharing' do
        before do
          trip.update!(sharing_settings: {
                         'enabled' => true,
                         'expiration' => '1h',
                         'expires_at' => 2.hours.ago.iso8601
                       })
        end

        it 'redirects to root with alert' do
          get shared_trip_url(trip.sharing_uuid)

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq('Shared trip not found or no longer available')
        end
      end

      context 'with disabled sharing' do
        before do
          trip.enable_sharing!(expiration: '24h')
          trip.disable_sharing!
        end

        it 'redirects to root with alert' do
          get shared_trip_url(trip.sharing_uuid)

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq('Shared trip not found or no longer available')
        end
      end

      context 'when trip has no path data' do
        before do
          trip.enable_sharing!(expiration: '24h')
          trip.update_column(:path, nil)
        end

        it 'renders successfully with placeholder' do
          get shared_trip_url(trip.sharing_uuid)

          expect(response).to have_http_status(:success)
          expect(response.body).to include('Route data not yet calculated')
        end
      end
    end

    describe 'PATCH /trips/:id/sharing' do
      context 'when user is signed in' do
        before { sign_in user }

        context 'enabling sharing' do
          it 'enables sharing and returns success' do
            patch sharing_trip_path(trip),
                  params: { enabled: '1', expiration: '24h' },
                  as: :json

            expect(response).to have_http_status(:success)

            json_response = JSON.parse(response.body)
            expect(json_response['success']).to be(true)
            expect(json_response['sharing_url']).to be_present
            expect(json_response['message']).to eq('Sharing enabled successfully')

            trip.reload
            expect(trip.sharing_enabled?).to be(true)
            expect(trip.sharing_uuid).to be_present
          end

          it 'enables sharing with notes option' do
            patch sharing_trip_path(trip),
                  params: { enabled: '1', expiration: '24h', share_notes: '1' },
                  as: :json

            expect(response).to have_http_status(:success)

            trip.reload
            expect(trip.sharing_enabled?).to be(true)
            expect(trip.share_notes?).to be(true)
          end

          it 'enables sharing with photos option' do
            patch sharing_trip_path(trip),
                  params: { enabled: '1', expiration: '24h', share_photos: '1' },
                  as: :json

            expect(response).to have_http_status(:success)

            trip.reload
            expect(trip.sharing_enabled?).to be(true)
            expect(trip.share_photos?).to be(true)
          end

          it 'sets custom expiration when provided' do
            patch sharing_trip_path(trip),
                  params: { enabled: '1', expiration: '1h' },
                  as: :json

            expect(response).to have_http_status(:success)
            trip.reload
            expect(trip.sharing_enabled?).to be(true)
            expect(trip.sharing_settings['expiration']).to eq('1h')
          end

          it 'enables permanent sharing' do
            patch sharing_trip_path(trip),
                  params: { enabled: '1', expiration: 'permanent' },
                  as: :json

            expect(response).to have_http_status(:success)
            trip.reload
            expect(trip.sharing_settings['expiration']).to eq('permanent')
            expect(trip.sharing_settings['expires_at']).to be_nil
          end
        end

        context 'disabling sharing' do
          before do
            trip.enable_sharing!(expiration: '24h')
          end

          it 'disables sharing and returns success' do
            patch sharing_trip_path(trip),
                  params: { enabled: '0' },
                  as: :json

            expect(response).to have_http_status(:success)

            json_response = JSON.parse(response.body)
            expect(json_response['success']).to be(true)
            expect(json_response['message']).to eq('Sharing disabled successfully')

            trip.reload
            expect(trip.sharing_enabled?).to be(false)
          end
        end

        context 'when trip does not exist' do
          it 'returns not found' do
            patch sharing_trip_path(id: 999999),
                  params: { enabled: '1' },
                  as: :json

            expect(response).to have_http_status(:not_found)
          end
        end

        context 'when user is not the trip owner' do
          let(:other_user) { create(:user, email: 'other@example.com') }
          let(:other_trip) { create(:trip, user: other_user, name: 'Other Trip') }

          it 'returns not found' do
            patch sharing_trip_path(other_trip),
                  params: { enabled: '1' },
                  as: :json

            expect(response).to have_http_status(:not_found)
          end
        end
      end

      context 'when user is not signed in' do
        it 'returns unauthorized' do
          patch sharing_trip_path(trip),
                params: { enabled: '1' },
                as: :json

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end
end
