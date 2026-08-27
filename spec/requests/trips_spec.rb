# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/trips', type: :request do
  let(:valid_attributes) do
    {
      name: 'Summer Vacation 2024',
      started_at: Date.tomorrow,
      ended_at: Date.tomorrow + 7.days,
      notes: 'A wonderful week-long trip'
    }
  end

  let(:invalid_attributes) do
    {
      name: '', # name can't be blank
      start_date: nil, # dates are required
      end_date: Date.yesterday # end date can't be before start date
    }
  end
  let(:user) { create(:user) }

  before do
    allow_any_instance_of(Trip).to receive(:photos_by_day).and_return({})

    sign_in user
  end

  describe 'GET /index' do
    it 'renders a successful response' do
      get trips_url
      expect(response).to be_successful
    end

    context 'when trip path is not yet calculated' do
      let!(:trip_without_path) { create(:trip, user:, path: nil, distance: nil) }

      it 'renders a successful response with loading state' do
        get trips_url
        expect(response).to be_successful
        expect(response.body).to include('Calculating...')
      end
    end
  end

  describe 'GET /show' do
    let(:trip) { create(:trip, :with_points, user:) }

    it 'renders a successful response' do
      get trip_url(trip)

      expect(response).to be_successful
    end

    it 'renders the recalculate button' do
      get trip_url(trip)

      expect(response.body).to include('Recalculate')
    end

    it 'renders header edit and delete actions' do
      get trip_url(trip)

      expect(response.body).to include(edit_trip_path(trip))
      expect(response.body).to include('Delete this trip')
    end

    describe 'poster studio' do
      it 'renders the studio without date controls' do
        get trip_url(trip)

        expect(response.body).to include('id="poster-studio"')
        expect(response.body).not_to include('data-poster-studio-editor-target="dateStart"')
      end

      it 'passes the trip name to the map controller' do
        get trip_url(trip)

        expect(response.body).to include("data-trip-maplibre-trip-name-value=\"#{trip.name}\"")
      end

      it 'renders an enabled poster button when the path exists' do
        get trip_url(trip)

        button = Nokogiri::HTML(response.body).at_css('[data-trip-maplibre-target="posterBtn"]')
        expect(button).to be_present
        expect(button['disabled']).to be_nil
      end

      it 'renders a disabled poster button while the path is calculating' do
        trip.update_columns(path: nil)

        get trip_url(trip)

        button = Nokogiri::HTML(response.body).at_css('[data-trip-maplibre-target="posterBtn"]')
        expect(button['disabled']).to be_present
        expect(button['title']).to eq('Available once the trip route is calculated')
      end

      it 'renders the poster gallery list' do
        create(:poster, user:)

        get trip_url(trip)

        expect(response.body).to include('poster-gallery-list')
      end
    end

    context 'with photos grouped by day' do
      let(:photo) do
        { id: 7, url: '/api/v1/photos/7/thumbnail.jpg?api_key=x&source=immich',
          source: 'immich', orientation: 'landscape' }
      end

      before do
        allow_any_instance_of(Trip).to receive(:photos_by_day)
          .and_return({ Date.new(2024, 11, 28) => [photo] })
      end

      it "renders a day's photos inside that day's collapse" do
        get trip_url(trip)

        day = Nokogiri::HTML(response.body).at_css("details[data-day-key='2024-11-28']")
        expect(day.at_css("img[src='#{photo[:url]}']")).to be_present
      end

      it 'renders photo thumbnails only inside day collapses (no flat bottom grid)' do
        get trip_url(trip)

        imgs = Nokogiri::HTML(response.body).css("img[src*='/api/v1/photos/']")
        expect(imgs).to be_present
        expect(imgs).to all(satisfy { |img| img.ancestors('details').any? })
      end
    end

    it 'computes day stats with PostGIS (no Ruby Geocoder fallback)' do
      allow(Geocoder::Calculations).to receive(:distance_between).and_call_original

      get trip_url(trip)

      expect(response).to be_successful
      expect(Geocoder::Calculations).not_to have_received(:distance_between)
    end

    context 'when the user timezone is not UTC' do
      before { user.update!(settings: user.settings.merge('timezone' => 'Europe/Berlin')) }

      let(:boundary_trip) do
        create(:trip, user:, started_at: Time.utc(2025, 1, 15), ended_at: Time.utc(2025, 1, 16, 23, 59, 59))
      end

      it 'buckets a point just after local midnight into its correct local day' do
        create(:point, user:, timestamp: Time.utc(2025, 1, 15, 12, 0).to_i, latitude: 52.0, longitude: 13.0)
        create(:point, user:, timestamp: Time.utc(2025, 1, 15, 23, 30).to_i, latitude: 52.6, longitude: 13.4)

        get trip_url(boundary_trip)

        day = Nokogiri::HTML(response.body).at_css("details[data-day-key='2025-01-16']")
        expect(day.text).to include('00:30')
        expect(day.text).not_to include('No data')
      end

      it 'renders successfully when the timezone is a non-IANA ActiveSupport name' do
        user.update!(settings: user.settings.merge('timezone' => 'Berlin'))
        create(:point, user:, timestamp: Time.utc(2025, 1, 15, 12, 0).to_i, latitude: 52.0, longitude: 13.0)

        get trip_url(boundary_trip)

        expect(response).to be_successful
      end
    end
  end

  describe 'GET /new' do
    it 'renders a successful response' do
      get new_trip_url

      expect(response).to be_successful
    end

    context 'when user is inactive' do
      before do
        user.update(status: :inactive, active_until: 1.day.ago)
      end

      it 'redirects to the root path' do
        get new_trip_url

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq('Your account is not active.')
      end
    end
  end

  describe 'GET /edit' do
    let(:trip) { create(:trip, :with_points, user:) }

    it 'renders a successful response' do
      get edit_trip_url(trip)

      expect(response).to be_successful
    end
  end

  describe 'POST /create' do
    context 'with valid parameters' do
      it 'creates a new Trip' do
        expect do
          post trips_url, params: { trip: valid_attributes }
        end.to change(Trip, :count).by(1)
      end

      it 'redirects to the created trip' do
        post trips_url, params: { trip: valid_attributes }
        expect(response).to redirect_to(trip_url(Trip.last))
      end

      context 'when user is inactive' do
        before do
          user.update(status: :inactive, active_until: 1.day.ago)
        end

        it 'redirects to the root path' do
          post trips_url, params: { trip: valid_attributes }

          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to eq('Your account is not active.')
        end
      end
    end

    context 'with invalid parameters' do
      it 'does not create a new Trip' do
        expect do
          post trips_url, params: { trip: invalid_attributes }
        end.to change(Trip, :count).by(0)
      end

      it "renders a response with 422 status (i.e. to display the 'new' template)" do
        post trips_url, params: { trip: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'PATCH /update' do
    context 'with valid parameters' do
      let(:new_attributes) do
        {
          name: 'Updated Trip Name',
          description: 'Changed trip notes'
        }
      end
      let(:trip) { create(:trip, :with_points, user:) }

      it 'updates the requested trip' do
        patch trip_url(trip), params: { trip: new_attributes }
        trip.reload

        expect(trip.name).to eq('Updated Trip Name')
        expect(trip.description.body.to_plain_text).to eq('Changed trip notes')
        expect(trip.description).to be_an(ActionText::RichText)
      end

      it 'redirects to the trip' do
        patch trip_url(trip), params: { trip: new_attributes }
        trip.reload

        expect(response).to redirect_to(trip_url(trip))
      end
    end

    context 'with invalid parameters' do
      let(:trip) { create(:trip, :with_points, user:) }

      it 'renders a response with 422 status' do
        patch trip_url(trip), params: { trip: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'DELETE /destroy' do
    let!(:trip) { create(:trip, :with_points, user:) }

    it 'destroys the requested trip' do
      expect do
        delete trip_url(trip)
      end.to change(Trip, :count).by(-1)
    end

    it 'redirects to the trips list' do
      delete trip_url(trip)

      expect(response).to redirect_to(trips_url)
    end
  end
end
