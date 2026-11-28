# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trips list does not embed route coordinates', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'previews a long recorded route without sending its vertices' do
    vertices = Array.new(20_000) { |i| format('%.5f -40.00000', -150 + (i * 0.0005)) }
    trip = create(:trip, user:, path: "LINESTRING(#{vertices.join(', ')})", skip_calculation_enqueue: true)

    get trips_path

    expect(response.body).not_to include('-144.9995')
    card = Nokogiri::HTML(response.body).at_css("#trip-#{trip.id} [data-controller='trip-maplibre-preview']")
    expect(card['data-trip-maplibre-preview-tiles-url-value']).to include("/api/v1/tiles/trips/#{trip.id}/")
  end
end
