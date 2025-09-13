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
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})

    allow_any_instance_of(Trip).to receive(:photo_previews).and_return([])

    sign_in user
  end

  describe 'GET /index' do
    it 'renders a successful response' do
      get trips_url
      expect(response).to be_successful
    end
  end

  describe 'GET /show' do
    let(:trip) { create(:trip, :with_points, user:) }

    it 'renders a successful response' do
      get trip_url(trip)

      expect(response).to be_successful
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
          notes: 'Changed trip notes'
        }
      end
      let(:trip) { create(:trip, :with_points, user:) }

      it 'updates the requested trip' do
        patch trip_url(trip), params: { trip: new_attributes }
        trip.reload

        expect(trip.name).to eq('Updated Trip Name')
        expect(trip.notes.body.to_plain_text).to eq('Changed trip notes')
        expect(trip.notes).to be_an(ActionText::RichText)
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
