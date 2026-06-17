# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Places', type: :request do
  let(:user) { create(:user) }
  let!(:place) { create(:place, user: user, name: 'Home', latitude: 40.7128, longitude: -74.0060) }
  let!(:tag) { create(:tag, user: user, name: 'Favorite') }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  describe 'GET /api/v1/places' do
    it 'returns user places' do
      get '/api/v1/places', headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json.size).to eq(1)
      expect(json.first['name']).to eq('Home')
    end

    it 'filters by tag_ids' do
      tagged_place = create(:place, user: user)
      create(:tagging, taggable: tagged_place, tag: tag)

      get '/api/v1/places', params: { tag_ids: [tag.id] }, headers: headers

      json = JSON.parse(response.body)
      expect(json.size).to eq(1)
      expect(json.first['id']).to eq(tagged_place.id)
    end

    it 'does not return other users places' do
      other_user = create(:user)
      create(:place, user: other_user, name: 'Private Place')

      get '/api/v1/places', headers: headers

      json = JSON.parse(response.body)
      expect(json.map { |p| p['name'] }).not_to include('Private Place')
    end

    context 'map visibility (manual + confirmed + tagged only)' do
      it 'excludes a suggested-only photon place' do
        suggested = create(:place, user: user, name: 'Suggested Only', source: :photon)
        create(:visit, user: user, place: suggested, area: nil, status: :suggested)

        get '/api/v1/places', headers: headers

        json = JSON.parse(response.body)
        expect(json.map { |p| p['name'] }).not_to include('Suggested Only')
      end

      it 'includes a photon place linked to a confirmed visit' do
        confirmed = create(:place, user: user, name: 'Confirmed Place', source: :photon)
        create(:visit, user: user, place: confirmed, area: nil, status: :confirmed)

        get '/api/v1/places', headers: headers

        json = JSON.parse(response.body)
        expect(json.map { |p| p['name'] }).to include('Confirmed Place')
      end

      it 'includes a manual place with no visits' do
        create(:place, user: user, name: 'Manual Pin', source: :manual)

        get '/api/v1/places', headers: headers

        json = JSON.parse(response.body)
        expect(json.map { |p| p['name'] }).to include('Manual Pin')
      end

      it 'includes a tagged photon place even when its only visit is suggested' do
        tagged = create(:place, user: user, name: 'Tagged Suggested', source: :photon)
        create(:tagging, taggable: tagged, tag: tag)
        create(:visit, user: user, place: tagged, area: nil, status: :suggested)

        get '/api/v1/places', headers: headers

        json = JSON.parse(response.body)
        expect(json.map { |p| p['name'] }).to include('Tagged Suggested')
      end
    end

    context 'with filter param' do
      let!(:suggested) do
        place = create(:place, user: user, name: 'Suggested Only', source: :photon)
        create(:visit, user: user, place: place, area: nil, status: :suggested)
        place
      end
      let!(:confirmed) do
        place = create(:place, user: user, name: 'Confirmed Place', source: :photon)
        create(:visit, user: user, place: place, area: nil, status: :confirmed)
        place
      end

      it 'filter=all returns every place including suggested-only' do
        get '/api/v1/places', params: { filter: 'all' }, headers: headers

        names = JSON.parse(response.body).map { |p| p['name'] }
        expect(names).to include('Suggested Only', 'Confirmed Place', 'Home')
      end

      it 'filter=manual returns only manually created places' do
        get '/api/v1/places', params: { filter: 'manual' }, headers: headers

        names = JSON.parse(response.body).map { |p| p['name'] }
        expect(names).to include('Home')
        expect(names).not_to include('Suggested Only', 'Confirmed Place')
      end

      it 'filter=confirmed returns only places linked to confirmed visits' do
        get '/api/v1/places', params: { filter: 'confirmed' }, headers: headers

        names = JSON.parse(response.body).map { |p| p['name'] }
        expect(names).to include('Confirmed Place')
        expect(names).not_to include('Suggested Only', 'Home')
      end

      it 'filter=tagged returns only tagged places' do
        tagged = create(:place, user: user, name: 'Tagged Place', source: :photon)
        create(:tagging, taggable: tagged, tag: tag)

        get '/api/v1/places', params: { filter: 'tagged' }, headers: headers

        names = JSON.parse(response.body).map { |p| p['name'] }
        expect(names).to include('Tagged Place')
        expect(names).not_to include('Home', 'Suggested Only', 'Confirmed Place')
      end

      it 'defaults to map-visible filtering when filter is unknown' do
        get '/api/v1/places', params: { filter: 'bogus' }, headers: headers

        names = JSON.parse(response.body).map { |p| p['name'] }
        expect(names).not_to include('Suggested Only')
        expect(names).to include('Confirmed Place', 'Home')
      end
    end
  end

  describe 'GET /api/v1/places/:id' do
    it 'returns the place' do
      get "/api/v1/places/#{place.id}", headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['name']).to eq('Home')
      expect(json['latitude']).to eq(40.7128)
    end

    it 'returns 404 for other users place' do
      other_user = create(:user)
      other_place = create(:place, user: other_user)

      get "/api/v1/places/#{other_place.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/places' do
    let(:valid_params) do
      {
        place: {
          name: 'Central Park',
          latitude: 40.785091,
          longitude: -73.968285,
          source: 'manual',
          tag_ids: [tag.id]
        }
      }
    end

    it 'creates a place' do
      expect do
        post '/api/v1/places', params: valid_params, headers: headers
      end.to change(Place, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['name']).to eq('Central Park')
    end

    it 'associates tags with the place' do
      post '/api/v1/places', params: valid_params, headers: headers

      place = Place.last
      expect(place.tags).to include(tag)
    end

    it 'returns errors for invalid params' do
      post '/api/v1/places', params: { place: { name: '' } }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['errors']).to be_present
    end
  end

  describe 'PATCH /api/v1/places/:id' do
    it 'updates the place' do
      patch "/api/v1/places/#{place.id}",
            params: { place: { name: 'Updated Home' } },
            headers: headers

      expect(response).to have_http_status(:success)
      expect(place.reload.name).to eq('Updated Home')
    end

    it 'updates tags' do
      new_tag = create(:tag, user: user, name: 'Work')

      patch "/api/v1/places/#{place.id}",
            params: { place: { tag_ids: [new_tag.id] } },
            headers: headers

      expect(place.reload.tags).to contain_exactly(new_tag)
    end

    it 'prevents updating other users places' do
      other_user = create(:user)
      other_place = create(:place, user: other_user)

      patch "/api/v1/places/#{other_place.id}",
            params: { place: { name: 'Hacked' } },
            headers: headers

      expect(response).to have_http_status(:not_found)
      expect(other_place.reload.name).not_to eq('Hacked')
    end
  end

  describe 'DELETE /api/v1/places/:id' do
    it 'destroys the place' do
      expect do
        delete "/api/v1/places/#{place.id}", headers: headers
      end.to change(Place, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it 'prevents deleting other users places' do
      other_user = create(:user)
      other_place = create(:place, user: other_user)

      expect do
        delete "/api/v1/places/#{other_place.id}", headers: headers
      end.not_to change(Place, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/places/nearby' do
    before do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    end

    it 'returns nearby places from geocoder', :vcr do
      get '/api/v1/places/nearby',
          params: { latitude: 40.7128, longitude: -74.0060 },
          headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['places']).to be_an(Array)
    end

    it 'requires latitude and longitude' do
      get '/api/v1/places/nearby', headers: headers

      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json['error']).to include('latitude and longitude')
    end

    it 'accepts custom radius and limit' do
      service_double = instance_double(Places::NearbySearch)
      allow(Places::NearbySearch).to receive(:new)
        .with(latitude: 40.7128, longitude: -74.0060, radius: 1.0, limit: 5)
        .and_return(service_double)
      allow(service_double).to receive(:call).and_return([])

      get '/api/v1/places/nearby',
          params: { latitude: 40.7128, longitude: -74.0060, radius: 1.0, limit: 5 },
          headers: headers

      expect(response).to have_http_status(:success)
    end
  end

  describe 'authentication' do
    it 'requires API key for all endpoints' do
      get '/api/v1/places'
      expect(response).to have_http_status(:unauthorized)

      post '/api/v1/places', params: { place: { name: 'Test' } }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
