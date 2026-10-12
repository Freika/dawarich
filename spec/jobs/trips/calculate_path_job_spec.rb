# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::CalculatePathJob do
  let(:user) { create(:user) }

  before { allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_to) }

  it 'refreshes open trip pages once the first path is calculated, so the map replaces the placeholder' do
    trip = create(:trip, :with_points, user:, path: nil)

    described_class.perform_now(trip.id)

    expect(trip.reload.path).to be_present
    expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_to).with(trip)
  end

  it 'leaves open trip pages alone when the trip already had a path' do
    trip = create(:trip, :with_points, user:)

    described_class.perform_now(trip.id)

    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_refresh_to)
  end
end
