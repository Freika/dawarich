# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trek calculation handover' do
  it 'enqueues after commit for the owned trip and ignores a foreign owner' do
    user = create(:user)
    trip = create(:trip, user:)
    clear_enqueued_jobs
    handler = RailsCommands::Registry.handler('trips.calculate')
    payload = { 'user_id' => user.id, 'trip_id' => trip.id, 'distance_unit' => 'mi' }
    ActiveRecord::Base.transaction do
      handler.call(payload)
      expect(enqueued_jobs).to be_empty
    end
    expect(Trips::CalculateAllJob).to have_been_enqueued.with(trip.id, 'mi').exactly(:once)
    clear_enqueued_jobs
    other = create(:user)
    clear_enqueued_jobs
    handler.call(payload.merge('user_id' => other.id))
    expect(enqueued_jobs).to be_empty
  end
end
