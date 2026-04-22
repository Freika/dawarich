# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/places', type: :request do
  let(:user) { create(:user) }

  before do
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

  describe 'GET /show' do
    let!(:place) do
      create(:place, user:, name: 'Test Cafe', city: 'Berlin', country: 'Germany', source: :manual)
    end

    context 'when authenticated' do
      it 'returns a successful response' do
        get place_url(place)

        expect(response).to have_http_status(:ok)
      end

      it 'wraps the body in the place-drawer turbo-frame' do
        get place_url(place)

        expect(response.body).to include('turbo-frame')
        expect(response.body).to include('id="place-drawer"')
      end

      it 'renders the place name, city, and country' do
        get place_url(place)

        expect(response.body).to include('Test Cafe')
        expect(response.body).to include('Berlin')
        expect(response.body).to include('Germany')
      end

      it 'renders the total visit count' do
        create_list(:visit, 3, place:, user:, duration: 60, area: nil)

        get place_url(place)

        expect(response.body).to include('3 visits').or include('>3<')
      end

      it 'shows total dwell hours based on MINUTES column' do
        base_time = Time.zone.parse('2026-04-01 12:00')
        3.times do |i|
          create(
            :visit,
            place:,
            user:,
            duration: 60,
            started_at: base_time + i.days,
            ended_at: base_time + i.days + 1.hour,
            area: nil
          )
        end

        get place_url(place)

        # 3 visits * 60 minutes = 180 minutes = 3.0 hours
        expect(response.body).to include('3.0')
      end

      it 'shows average dwell formatted as Xh Ym' do
        base_time = Time.zone.parse('2026-04-01 12:00')
        [90, 90].each_with_index do |duration, i|
          create(
            :visit,
            place:,
            user:,
            duration: duration,
            started_at: base_time + i.days,
            ended_at: base_time + i.days + duration.minutes,
            area: nil
          )
        end

        get place_url(place)

        # avg = 90 min = 1h 30m
        expect(response.body).to include('1h 30m')
      end

      it 'lists up to 5 most recent visits ordered by started_at DESC' do
        base_time = Time.zone.parse('2026-04-01 12:00')
        7.times do |i|
          create(
            :visit,
            place:,
            user:,
            name: "Visit #{i}",
            duration: 30,
            started_at: base_time + i.hours,
            ended_at: base_time + i.hours + 30.minutes,
            area: nil
          )
        end

        get place_url(place)

        # Most recent is Visit 6; oldest two (0, 1) should not appear in the body
        # of the drawer's recent-visits list
        expect(response.body.scan(/Visit \d/).size).to be <= 5
        expect(response.body).to include('Visit 6')
        expect(response.body).not_to include('Visit 0')
      end
    end

    context 'when unauthenticated' do
      before { sign_out user }

      it 'redirects to the sign-in page' do
        get place_url(place)

        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('/users/sign_in')
      end
    end

    context "when accessing another user's place" do
      let(:other_user) { create(:user) }
      let!(:other_place) { create(:place, user: other_user) }

      it 'returns 404' do
        get place_url(other_place)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PATCH /update from drawer frame' do
    let!(:place) { create(:place, user:, name: 'Drawer Place') }

    it 'returns a turbo_stream that replaces the place-drawer frame' do
      patch place_url(place),
            params: { place: { note: 'Updated note' } },
            headers: { 'Turbo-Frame' => 'place-drawer' },
            as: :turbo_stream

      expect(place.reload.note).to eq('Updated note')
      expect_turbo_stream_response
      expect_turbo_stream_action('replace', 'place-drawer')
    end
  end
end
