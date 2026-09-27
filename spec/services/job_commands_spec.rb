# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JobCommands do
  let(:trip_payload) { { 'trip_id' => 42, 'distance_unit' => 'km' } }

  def produce_trip
    described_class.produce('trips.calculate', trip_payload, aggregate_id: 42, dedupe_key: '42', producer: 'spec')
  end

  it 'enqueues the Sidekiq job when Phoenix never migrated the database' do
    expect { expect(produce_trip).to eq(:sidekiq) }.to have_enqueued_job(Trips::CalculateAllJob).with(42, 'km')
    expect(JobOutbox.count).to eq(0)
  end

  it 'enqueues the Sidekiq job while Sidekiq owns the key' do
    job_owner!('command:trips.calculate', :sidekiq)

    expect { produce_trip }.to have_enqueued_job(Trips::CalculateAllJob)
  end

  it 'writes a typed command instead when Oban owns the key' do
    job_owner!('command:trips.calculate', :oban)

    expect { expect(produce_trip).to eq(:outbox) }.not_to have_enqueued_job
    row = JobOutbox.sole
    expect(row).to have_attributes(command_type: 'trips.calculate', command_version: 1, payload: trip_payload,
                                   aggregate_id: 42, dedupe_key: '42', state: 'pending',
                                   metadata: { 'producer' => 'spec' })
  end

  it 'joins the caller transaction, so a rolled-back domain write produces nothing' do
    job_owner!('command:trips.calculate', :oban)

    ActiveRecord::Base.transaction do
      produce_trip
      raise ActiveRecord::Rollback
    end

    expect(JobOutbox.count).to eq(0)
  end

  it 'collapses repeated commands for the same pending trip' do
    job_owner!('command:trips.calculate', :oban)

    3.times { produce_trip }

    expect(JobOutbox.pending.count).to eq(1)
  end

  it 'forwards an event once however often a Sidekiq retry forwards it' do
    event_id = SecureRandom.uuid
    args = [{ 'user_id' => 1, 'locale' => 'de' }, { event_id:, aggregate_id: 1, producer: 'spec' }]

    expect(described_class.forward('users.explore_features_mail', args[0], **args[1])).to eq(1)
    expect(described_class.forward('users.explore_features_mail', args[0], **args[1])).to eq(0)
  end

  it 'cancels only the pending commands of one aggregate' do
    job_owner!('command:users.explore_features_mail', :oban)
    %w[7 8].each do |id|
      described_class.produce('users.explore_features_mail', { 'user_id' => id.to_i, 'locale' => 'en' },
                              aggregate_id: id.to_i, scheduled_at: 2.days.from_now, producer: 'spec')
    end

    expect(described_class.cancel_pending('users.explore_features_mail', 7)).to eq(1)
    expect(JobOutbox.pluck(:aggregate_id)).to eq([8])
  end

  it 're-homes pending commands to Sidekiq with their schedule and locale, and leaves dispatched ones' do
    job_owner!('command:users.explore_features_mail', :oban)
    at = 2.days.from_now.change(usec: 0)
    described_class.produce('users.explore_features_mail', { 'user_id' => 5, 'locale' => 'de' },
                            aggregate_id: 5, scheduled_at: at, producer: 'spec')
    JobOutbox.create!(event_id: SecureRandom.uuid, command_type: 'users.explore_features_mail', command_version: 1,
                      payload: { 'user_id' => 6, 'locale' => 'en' }, scheduled_at: at, state: 'dispatched')

    expect do
      expect(described_class.rehome!('users.explore_features_mail', by: 'spec')).to eq({ moved: 1, left: 0 })
    end
      .to have_enqueued_job(Users::MailerSendingJob).with(5, 'explore_features').at(at)
    expect(enqueued_jobs.last['locale']).to eq('de')
    expect(JobOutbox.pluck(:state)).to eq(['dispatched'])
  end

  it 'leaves a pending command with a mismatched command_version untouched' do
    job_owner!('command:trips.calculate', :oban)
    produce_trip
    JobOutbox.update_all(command_version: 2)

    expect { expect(described_class.rehome!('trips.calculate', by: 'spec')).to eq({ moved: 0, left: 0 }) }
      .not_to have_enqueued_job(Trips::CalculateAllJob)
    expect(JobOutbox.pluck(:command_version, :state)).to eq([[2, 'pending']])
  end

  it 'releases the key to a pinned Sidekiq owner in the same transaction, so the re-homed job runs in Sidekiq' do
    job_owner!('command:users.explore_features_mail', :oban)
    described_class.produce('users.explore_features_mail', { 'user_id' => 5, 'locale' => 'en' },
                            aggregate_id: 5, scheduled_at: 2.days.from_now, producer: 'spec')

    described_class.rehome!('users.explore_features_mail', by: 'spec')

    owner = ActiveRecord::Base.connection.select_rows(
      "SELECT owner, pinned, updated_by FROM phoenix.job_owners WHERE key = 'command:users.explore_features_mail'"
    )
    expect(owner).to eq([['sidekiq', true, 'spec']])
    expect(JobOwnership.with_owner('command:users.explore_features_mail') { :sidekiq_runs }).to eq(:sidekiq_runs)
  end

  it 'replays only quarantined commands, keeping the event id and auditing who and why' do
    phoenix_tables!
    row = JobOutbox.create!(event_id: SecureRandom.uuid, command_type: 'trips.calculate', command_version: 1,
                            payload: trip_payload, scheduled_at: Time.current, state: 'quarantined',
                            error_code: 'unsupported_version')

    described_class.replay!(row.event_id, actor: 'rake:eugene', reason: 'decoder fixed')

    expect(row.reload).to have_attributes(state: 'pending', error_code: nil)
    expect(ActiveRecord::Base.connection.select_rows('SELECT actor, reason FROM phoenix.job_outbox_replays'))
      .to eq([['rake:eugene', 'decoder fixed']])
    expect { described_class.replay!(row.event_id, actor: 'x', reason: 'y') }.to raise_error(ArgumentError, /pending/)
  end

  describe 'rehome! while a relay holds a pending command' do
    self.use_transactional_tests = false

    let(:event_ids) { [SecureRandom.uuid, SecureRandom.uuid] }

    after do
      JobOutbox.where(event_id: event_ids).delete_all
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '2s'")
        ActiveRecord::Base.connection.execute('DROP SCHEMA IF EXISTS phoenix CASCADE')
      end
    end

    it 'moves unlocked commands and reports the pending command left behind by the relay' do
      job_owner!('command:trips.calculate', :oban)
      event_ids.each_with_index do |event_id, index|
        described_class.forward('trips.calculate', { 'trip_id' => index + 1, 'distance_unit' => 'km' }, event_id:,
                                aggregate_id: index + 1, producer: 'spec')
      end
      holding = Queue.new
      release = Queue.new
      holder = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.transaction do
            connection.execute("SET LOCAL lock_timeout = '2s'")
            connection.execute("SELECT 1 FROM job_outbox WHERE event_id = '#{event_ids.first}' FOR UPDATE")
            holding << true
            release.pop
          end
        end
      end

      begin
        Timeout.timeout(5) { holding.pop }

        expect do
          expect(described_class.rehome!('trips.calculate', by: 'spec')).to eq({ moved: 1, left: 1 })
        end.to have_enqueued_job(Trips::CalculateAllJob).with(2, 'km')
        expect(JobOutbox.where(event_id: event_ids)).to contain_exactly(
          have_attributes(event_id: event_ids.first, state: 'pending')
        )
      ensure
        release << true
        raise 'holder thread did not finish: still holding the outbox row lock' unless holder.join(5)
      end
    end
  end

  describe 'produce joining the caller transaction across a real commit/rollback' do
    self.use_transactional_tests = false

    after do
      JobOutbox.where(command_type: 'trips.calculate', aggregate_id: 42).delete_all
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '2s'")
        ActiveRecord::Base.connection.execute('DROP SCHEMA IF EXISTS phoenix CASCADE')
      end
    end

    it 'leaves no outbox row when the caller transaction rolls back' do
      job_owner!('command:trips.calculate', :oban)

      ActiveRecord::Base.transaction do
        produce_trip
        raise ActiveRecord::Rollback
      end

      expect(JobOutbox.count).to eq(0)
    end

    it 'writes exactly one outbox row when the caller transaction commits' do
      job_owner!('command:trips.calculate', :oban)

      ActiveRecord::Base.transaction { produce_trip }

      expect(JobOutbox.count).to eq(1)
    end
  end
end
