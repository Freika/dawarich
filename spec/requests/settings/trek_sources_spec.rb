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
end
