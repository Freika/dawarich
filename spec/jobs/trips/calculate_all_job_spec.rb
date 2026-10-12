# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::CalculateAllJob, type: :job do
  let(:user) { create(:user) }
  let(:trip) do
    create(:trip,
           user: user,
           started_at: DateTime.new(2024, 11, 27, 12, 0, 0),
           ended_at: DateTime.new(2024, 11, 27, 14, 0, 0))
  end
  let(:run_token) { SecureRandom.uuid }

  describe '#perform' do
    it 'enqueues the three sub-jobs with a generated run_token and seeds the pending counter' do
      allow(SecureRandom).to receive(:uuid).and_return(run_token)

      described_class.perform_now(trip.id, 'km')

      expect(Trips::CalculatePathJob).to have_been_enqueued.with(trip.id, run_token)
      expect(Trips::CalculateDistanceJob).to have_been_enqueued.with(trip.id, 'km', run_token)
      expect(Trips::CalculateCountriesJob).to have_been_enqueued.with(trip.id, 'km', run_token)
      expect(Rails.cache.read(described_class.pending_key(trip.id, run_token), raw: true).to_i).to eq(3)
    end
  end

  describe '.tally_completion' do
    before do
      Rails.cache.write(described_class.pending_key(trip.id, run_token), 3, expires_in: 5.minutes, raw: true)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    after { Rails.cache.delete(described_class.pending_key(trip.id, run_token)) }

    it 'is a no-op when run_token is nil (sub-job invoked outside an orchestrated chain)' do
      described_class.tally_completion(trip.id, nil)

      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end

    it 'is a no-op when the cache key is gone (stale tally from a previous run)' do
      stale_token = SecureRandom.uuid

      described_class.tally_completion(trip.id, stale_token)

      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end

    it 'decrements the counter without finalizing while sub-jobs remain' do
      described_class.tally_completion(trip.id, run_token)

      expect(Rails.cache.read(described_class.pending_key(trip.id, run_token), raw: true).to_i).to eq(2)
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end

    it 'finalizes success after the third decrement and clears the counter' do
      trip.update_column(:last_recalculated_at, Time.current)

      3.times { described_class.tally_completion(trip.id, run_token) }

      expect(Rails.cache.read(described_class.pending_key(trip.id, run_token), raw: true)).to be_nil
      expect(trip.reload.last_recalculated_at).to be_nil
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        trip_record_for(trip.id),
        hash_including(target: 'trip_recalculate_frame', locals: hash_including(error: false))
      )
    end

    it 'short-circuits to error finalize on error: true and clears the counter' do
      trip.update_column(:last_recalculated_at, Time.current)

      described_class.tally_completion(trip.id, run_token, error: true)

      expect(Rails.cache.read(described_class.pending_key(trip.id, run_token), raw: true)).to be_nil
      expect(trip.reload.last_recalculated_at).to be_nil
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        trip_record_for(trip.id),
        hash_including(target: 'trip_recalculate_frame', locals: hash_including(error: true))
      )
    end

    it 'no-ops finalize cleanly when the trip has been deleted mid-run' do
      trip_id = trip.id
      trip.destroy!

      expect { described_class.tally_completion(trip_id, run_token) }.not_to raise_error
    end
  end

  def trip_record_for(id)
    satisfy { |arg| arg.is_a?(Trip) && arg.id == id }
  end
end
