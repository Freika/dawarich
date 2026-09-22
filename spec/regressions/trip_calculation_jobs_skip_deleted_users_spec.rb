# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip calculation jobs after account deletion', type: :job do
  let(:user) { create(:user) }
  let(:trip) { create(:trip, user:) }
  let(:run_token) { SecureRandom.uuid }

  before do
    trip
    user.mark_as_deleted!
    allow(Trips::CalculateAllJob).to receive(:tally_completion)
  end

  {
    Trips::CalculatePathJob => ->(trip_id, token) { [trip_id, token] },
    Trips::CalculateDistanceJob => ->(trip_id, token) { [trip_id, 'km', token] },
    Trips::CalculateCountriesJob => ->(trip_id, token) { [trip_id, 'km', token] }
  }.each do |job_class, arguments|
    it "discards #{job_class.name} without calculating deleted-user data" do
      expect do
        job_class.perform_now(*arguments.call(trip.id, run_token))
      end.not_to raise_error

      expect(Trips::CalculateAllJob).to have_received(:tally_completion)
        .with(trip.id, run_token, error: true)
    end
  end
end
