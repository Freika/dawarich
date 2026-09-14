# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings::TrekSources', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
    allow(Resolv).to receive(:getaddress).with('trek.example.test').and_return('93.184.216.34')
  end

  describe 'POST /settings/trek_sources' do
    it 'verifies a source before saving it and then asks the user to choose trips' do
      stub_request(:get, 'https://trek.example.test/api/v1/trips')
        .with(headers: { 'Authorization' => 'Bearer trek_test_key' })
        .to_return(status: 200, body: { trips: [] }.to_json)

      expect do
        post settings_trek_sources_path,
             params: { trip_source: { base_url: 'https://trek.example.test/', api_key: 'trek_test_key' } }
      end.to change(user.trip_sources, :count).by(1)

      source = user.trip_sources.last
      expect(response).to redirect_to(select_trips_settings_trek_source_path(source))
      expect(source.base_url).to eq('https://trek.example.test')
    end

    it 'reconnects an existing disabled source with a replacement API key' do
      source = create(
        :trip_source, user: user, status: :disabled, api_key: 'expired_key', last_error: '401 Unauthorized'
      )
      stub_request(:get, 'https://trek.example.test/api/v1/trips')
        .with(headers: { 'Authorization' => 'Bearer replacement_key' })
        .to_return(status: 200, body: { trips: [] }.to_json)

      expect do
        post settings_trek_sources_path,
             params: { trip_source: { base_url: 'https://trek.example.test/', api_key: 'replacement_key' } }
      end.not_to change(user.trip_sources, :count)

      expect(source.reload).to have_attributes(api_key: 'replacement_key', status: 'active', last_error: nil)
      expect(response).to redirect_to(select_trips_settings_trek_source_path(source))
    end
  end

  describe 'DELETE /settings/trek_sources/:id' do
    it 'keeps imported trips while disconnecting their source' do
      source = create(:trip_source, user: user)
      trip = create(:trip, user: user, trip_source: source, source_identifier: '12', source_status: :active)

      expect do
        delete settings_trek_source_path(source)
      end.to change(TripSource, :count).by(-1)

      expect(trip.reload).to have_attributes(trip_source: nil, source_status: 'stopped')
      expect(response).to redirect_to(settings_integrations_path(service: 'trek'))
    end
  end

  describe 'POST /settings/trek_sources/:id/import_trips' do
    it 'stops syncing every selected trip when the selection is cleared' do
      source = create(:trip_source, user: user)
      trip = create(:trip, user: user, trip_source: source, source_identifier: 'existing', source_status: :active)

      post import_trips_settings_trek_source_path(source), params: { trip_ids: [] }

      expect(response).to redirect_to(settings_integrations_path(service: 'trek'))
      expect(trip.reload).to be_source_stopped
    end

    it 'stops syncing previously selected trips that are no longer selected' do
      source = create(:trip_source, user: user)
      previous_trip = create(
        :trip, user: user, trip_source: source, source_identifier: 'previous', source_status: :active
      )
      response_payload = {
        id: 12, title: 'Tuscany', start_date: '2030-06-14', end_date: '2030-06-22',
        days: [], unplanned_places: [], unscheduled_reservations: [], accommodations: [], travellers: []
      }

      stub_request(:get, 'https://trek.example.test/api/v1/trips')
        .to_return(status: 200, body: { trips: [{ id: 12, archived: false }] }.to_json)
      stub_request(:get, 'https://trek.example.test/api/v1/trips/12')
        .to_return(status: 200, body: response_payload.to_json)

      post import_trips_settings_trek_source_path(source), params: { trip_ids: ['12'] }

      expect(previous_trip.reload).to be_source_stopped
      expect(source.trips.find_by!(source_identifier: '12')).to be_source_active
    end

    it 'does not import archived trips submitted outside the selection UI' do
      source = create(:trip_source, user: user)
      stub_request(:get, 'https://trek.example.test/api/v1/trips')
        .to_return(status: 200, body: { trips: [{ id: 12, archived: true }] }.to_json)

      post import_trips_settings_trek_source_path(source), params: { trip_ids: ['12'] }

      expect(response).to redirect_to(select_trips_settings_trek_source_path(source))
      expect(source.trips).to be_empty
    end

    it 'does not change the current selection when more than 100 trips are submitted' do
      source = create(:trip_source, user: user)
      trip = create(:trip, user: user, trip_source: source, source_identifier: 'existing', source_status: :active)

      post import_trips_settings_trek_source_path(source), params: { trip_ids: (1..101).map(&:to_s) }

      expect(response).to redirect_to(select_trips_settings_trek_source_path(source))
      expect(trip.reload).to be_source_active
    end
  end
end
