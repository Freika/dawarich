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

  describe 'after Oban took trip calculations over' do
    let!(:trip) { create(:trip, skip_calculation_enqueue: true) }

    before { job_owner!(Trips::CalculateAllJob::OWNER_KEY, :oban) }

    def relay_dispatched_everything!
      JobOutbox.pending.update_all(state: 'dispatched')
    end

    def event_id(token)
      Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "trips.calculate:#{trip.id}:#{token}")
    end

    it 'forwards a queued run to the outbox instead of fanning out, once per job' do
      job = described_class.new(trip.id, 'mi')

      expect { job.perform_now }.not_to have_enqueued_job(Trips::CalculatePathJob)
      expect(JobOutbox.sole).to have_attributes(event_id: event_id(job.job_id),
                                                payload: { 'trip_id' => trip.id, 'distance_unit' => 'mi' })

      relay_dispatched_everything!
      job.perform_now

      expect(JobOutbox.count).to eq(1)
    end

    it 'forwards the three children of one run as one command, even after the first was dispatched' do
      token = SecureRandom.uuid

      Trips::CalculatePathJob.perform_now(trip.id, token)
      relay_dispatched_everything!
      Trips::CalculateDistanceJob.perform_now(trip.id, 'km', token)
      Trips::CalculateCountriesJob.perform_now(trip.id, 'km', token)

      expect(JobOutbox.sole.event_id).to eq(event_id(token))
      expect(trip.reload.distance).to eq(100)
    end

    it 'fans out in Sidekiq after rehome, although Oban owned the key' do
      JobCommands.produce('trips.calculate', { 'trip_id' => trip.id, 'distance_unit' => 'km' },
                          aggregate_id: trip.id, dedupe_key: trip.id.to_s, producer: 'spec')
      JobCommands.rehome!('trips.calculate', by: 'spec')

      perform_enqueued_jobs(only: described_class)

      expect(Trips::CalculatePathJob).to have_been_enqueued.with(trip.id, an_instance_of(String))
      expect(JobOutbox.count).to eq(0)
    end
  end

  describe 'the gate while Sidekiq owns trips (release N keeps today\'s behaviour)' do
    let!(:trip) { create(:trip, :with_points, path: nil, skip_calculation_enqueue: true) }
    let(:events) { [] }

    before do
      job_owner!(Trips::CalculateAllJob::OWNER_KEY, :sidekiq)
      %i[broadcast_refresh_to broadcast_update_to].each do |method|
        allow(Turbo::StreamsChannel).to receive(method) { events << :broadcast }
      end
    end

    def record(&block)
      callback = ->(*, payload) { events << payload[:sql] }
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    end

    def first_index(from = 0, &block)
      (from...events.size).find { |index| events[index].is_a?(String) && block.call(events[index]) }
    end

    {
      Trips::CalculatePathJob => ->(trip) { [trip.id] },
      Trips::CalculateDistanceJob => ->(trip) { [trip.id, 'km'] },
      Trips::CalculateCountriesJob => ->(trip) { [trip.id, 'km'] }
    }.each do |job_class, args|
      it "#{job_class.name.demodulize} computes before the gate, saves under it and broadcasts after its commit" do
        record { job_class.perform_now(*args.call(trip)) }

        reads = events.each_index.select do |index|
          events[index].is_a?(String) && events[index].include?('FROM "points"')
        end
        lock = first_index { _1.include?('FOR SHARE') }
        update = first_index(lock) { _1.start_with?('UPDATE "trips"') }
        commit = first_index(update) { _1.match?(/\A(RELEASE SAVEPOINT|COMMIT)/) }

        expect(reads).not_to be_empty
        expect(reads.max).to be < lock
        expect(first_index(lock) { _1.match?(/\A(RELEASE SAVEPOINT|COMMIT)/) }).to eq(commit)
        expect(events.index(:broadcast)).to be > commit
      end
    end
  end

  def trip_record_for(id)
    satisfy { |arg| arg.is_a?(Trip) && arg.id == id }
  end
end
