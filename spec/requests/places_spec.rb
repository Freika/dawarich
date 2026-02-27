# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/places', type: :request do
  let(:user) { create(:user) }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})

    sign_in user
  end

  describe 'GET /index' do
    it 'renders a successful response' do
      get places_url

      expect(response).to be_successful
    end
  end

  describe 'POST /create' do
    context 'with turbo_stream format' do
      let(:valid_params) { { place: { name: 'Coffee Shop', latitude: 52.52, longitude: 13.405, source: 'manual' } } }

      context 'with valid params' do
        it 'creates a new place' do
          expect do
            post places_url, params: valid_params, as: :turbo_stream
          end.to change(Place, :count).by(1)
        end

        it 'returns turbo_stream replacing place-creation-data with flash' do
          post places_url, params: valid_params, as: :turbo_stream

          expect_turbo_stream_response
          expect_turbo_stream_action('replace', 'place-creation-data')
          expect_flash_stream('Place created successfully!')
        end

        it 'includes created flag in response' do
          post places_url, params: valid_params, as: :turbo_stream

          expect(response.body).to include('data-created="true"')
        end

        it 'associates tags when provided' do
          tag1 = create(:tag, user:)
          params_with_tags = { place: { name: 'Tagged Place', latitude: 52.52, longitude: 13.405, tag_ids: [tag1.id] } }

          post places_url, params: params_with_tags, as: :turbo_stream

          expect(Place.last.tags).to include(tag1)
        end
      end

      context 'with invalid params' do
        let(:invalid_params) { { place: { name: '', latitude: 52.52, longitude: 13.405 } } }

        it 'does not create a place' do
          expect do
            post places_url, params: invalid_params, as: :turbo_stream
          end.not_to change(Place, :count)
        end

        it 'returns turbo_stream flash error' do
          post places_url, params: invalid_params, as: :turbo_stream

          expect_turbo_stream_response
          expect_flash_stream
        end
      end
    end
  end

  describe 'PATCH /update' do
    let!(:place) { create(:place, user:) }

    context 'with turbo_stream format' do
      it 'updates the place and returns turbo_stream' do
        patch place_url(place), params: { place: { name: 'Updated Name' } }, as: :turbo_stream

        expect(place.reload.name).to eq('Updated Name')
        expect_turbo_stream_response
        expect_turbo_stream_action('replace', 'place-creation-data')
        expect_flash_stream('Place updated successfully!')
      end

      it 'includes updated flag in response' do
        patch place_url(place), params: { place: { name: 'Updated' } }, as: :turbo_stream

        expect(response.body).to include('data-updated="true"')
      end

      it 'returns turbo_stream flash error with invalid params' do
        patch place_url(place), params: { place: { name: '' } }, as: :turbo_stream

        expect_turbo_stream_response
        expect_flash_stream
      end
    end
  end

  describe 'GET /nearby' do
    let(:geocoder_result) do
      double(
        'result',
        data: {
          'properties' => {
            'name' => 'Test Place',
            'city' => 'Berlin',
            'country' => 'Germany',
            'street' => 'Test Street',
            'housenumber' => '1',
            'osm_id' => 123
          },
          'geometry' => { 'coordinates' => [13.405, 52.52] }
        }
      )
    end

    before do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    end

    it 'returns nearby places partial with place cards' do
      allow(Geocoder).to receive(:search).and_return([geocoder_result])

      get nearby_places_url, params: { latitude: 52.52, longitude: 13.405 }

      expect(response).to be_successful
      expect(response.body).to include('data-place-name="Test Place"')
    end

    it 'returns bad request when coordinates are missing' do
      get nearby_places_url

      expect(response).to have_http_status(:bad_request)
    end

    it 'renders no results message when geocoder returns empty' do
      allow(Geocoder).to receive(:search).and_return([])

      get nearby_places_url, params: { latitude: 52.52, longitude: 13.405 }

      expect(response).to be_successful
      expect(response.body).to include('No nearby places found')
    end

    it 'renders no results when reverse geocoding is disabled' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)

      get nearby_places_url, params: { latitude: 52.52, longitude: 13.405 }

      expect(response).to be_successful
      expect(response.body).to include('No nearby places found')
    end
  end

  describe 'DELETE /destroy' do
    let!(:place) { create(:place, user:) }
    let!(:visit) { create(:visit, place:, user:) }

    it 'destroys the requested place' do
      expect do
        delete place_url(place)
      end.to change(Place, :count).by(-1)
    end

    it 'redirects to the places list' do
      delete place_url(place)

      expect(response).to redirect_to(places_url)
    end
  end
end
