# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BackfillState do
  include ActiveSupport::Testing::TimeHelpers
  self.use_transactional_tests = false
  after(:context) { self.class.use_transactional_tests = true }

  let(:user_id) { 48_301 }
  let(:other_id) { 48_302 }
  let(:now) { Time.utc(2026, 10, 4, 12) }
  let(:old) { now.to_i - 100_000 }

  before do
    phoenix_tables!
    phoenix_state!
    @original_owner = ActiveRecord::Base.connection.select_one(
      "SELECT * FROM phoenix.job_owners WHERE key = 'command:tracks.backfill'"
    )
  end

  after do
    connection = ActiveRecord::Base.connection
    connection.execute('DELETE FROM phoenix.track_backfill_ranges WHERE user_id IN (48301, 48302)')
    JobOutbox.where(command_type: 'tracks.backfill', aggregate_id: [user_id, other_id]).delete_all
    connection.execute("DELETE FROM phoenix.job_owners WHERE key = 'command:tracks.backfill'")
    if @original_owner
      columns = @original_owner.keys.join(', ')
      values = @original_owner.values.map { connection.quote(_1) }.join(', ')
      connection.execute("INSERT INTO phoenix.job_owners (#{columns}) VALUES (#{values})")
    end
    Sidekiq.redis { |redis| redis.del(range_key, schedule_key) }
    PhoenixSchema.reset!
  end

  def range_key = "track_backfill_range:user:#{user_id}"
  def schedule_key = "track_backfill:user:#{user_id}"

  def row
    ActiveRecord::Base.connection.select_one("SELECT * FROM phoenix.track_backfill_ranges WHERE user_id=#{user_id}")
  end

  def accumulate_batch(*timestamps) = described_class.new(user_id, timestamps).call

  def legacy!(first = old, last = old + 10)
    Sidekiq.redis do |redis|
      redis.zadd(range_key, first, first.to_s, last, last.to_s)
      redis.set(schedule_key, 1, ex: 300)
    end
  end

  it 'publishes once with shared bounds and rolls back state when native publication fails' do
    travel_to now do
      job_owner!('command:tracks.backfill', :oban)
      ActiveRecord::Base.transaction do
        accumulate_batch(old, old + 100)
        accumulate_batch(old - 100, old + 50)
        expect(JobOutbox.where(command_type: 'tracks.backfill', aggregate_id: user_id).count).to eq(1)
      end
      first = row
      expect(first).to include('earliest_timestamp' => old - 100, 'latest_timestamp' => old + 100)
      expect(JobOutbox.find_by!(aggregate_id: user_id).payload).to eq(
        'user_id' => user_id, 'cycle_id' => first.fetch('cycle_id'), 'time_zone' => Time.zone.name
      )
      described_class.pop_range(user_id)
      JobOutbox.where(aggregate_id: user_id).delete_all
      allow(JobCommands).to receive(:forward).and_wrap_original do |forward, *args, **opts|
        forward.call(*args, **opts)
        raise IOError, 'native publication failed'
      end
      expect { accumulate_batch(old) }.to raise_error(IOError, 'native publication failed')
      expect(row).to be_nil
      expect(JobOutbox.where(aggregate_id: user_id)).to be_empty
      allow(JobCommands).to receive(:forward).and_call_original
      job_owner!('command:tracks.backfill', :sidekiq)
      ActiveRecord::Base.transaction do
        accumulate_batch(old)
        expect(enqueued_jobs.select { _1[:job] == Tracks::BackfillGenerationJob }).to be_empty
      end
      expect(enqueued_jobs.count { _1[:job] == Tracks::BackfillGenerationJob }).to eq(1)
      described_class.pop_range(user_id)
      allow(Tracks::BackfillGenerationJob).to receive(:set).and_raise(IOError, 'Sidekiq unavailable')
      expect { accumulate_batch(old) }.to raise_error(IOError, 'Sidekiq unavailable')
      pending = row
      expect(pending).to include('earliest_timestamp' => old, 'latest_timestamp' => old, 'scheduled' => false)
      allow(Tracks::BackfillGenerationJob).to receive(:set).and_call_original
      accumulate_batch(old - 10)
      expect(row).to include('earliest_timestamp' => old - 10, 'scheduled' => true)
    end
  end

  it 'imports only an unchanged legacy user range after durable union' do
    travel_to now do
      job_owner!('command:tracks.backfill', :oban)
      legacy!
      allow(JobCommands).to receive(:forward).and_raise(IOError, 'SQL publication failed')
      expect { accumulate_batch(old + 20) }.to raise_error(IOError, 'SQL publication failed')
      expect(Sidekiq.redis { _1.zrange(range_key, 0, -1) }).to eq([old.to_s, (old + 10).to_s])
      expect(row).to be_nil
      allow(JobCommands).to receive(:forward).and_call_original
      ActiveRecord::Base.transaction do
        accumulate_batch(old + 20)
        expect(Sidekiq.redis { _1.zrange(range_key, 0, -1) }).to eq([old.to_s, (old + 10).to_s])
        legacy!(old - 30, old + 30)
      end
      expect(Sidekiq.redis { _1.zrange(range_key, 0, -1) }).to include((old - 30).to_s)
      accumulate_batch(old + 40)
      expect(row).to include('earliest_timestamp' => old - 30, 'latest_timestamp' => old + 40)
      expect(Sidekiq.redis { _1.exists(range_key) }).to eq(0)
      legacy!(old - 50, old + 50)
      uncertain = true
      allow_any_instance_of(RedisClient).to receive(:call).and_wrap_original do |call, *args|
        if uncertain && args.first == 'EVAL'
          uncertain = false
          raise RedisClient::ConnectionError, 'uncertain legacy removal'
        end
        call.call(*args)
      end
      accumulate_batch(old + 60)
      expect(Sidekiq.redis { _1.exists(range_key) }).to eq(1)
      allow_any_instance_of(RedisClient).to receive(:call).and_call_original
      legacy!(old - 70, old + 70)
      accumulate_batch(old + 80)
      expect(row).to include('earliest_timestamp' => old - 70, 'latest_timestamp' => old + 80)
      expect(JobOutbox.where(aggregate_id: user_id).count).to eq(1)
      described_class.pop_range(user_id)
      legacy!(old - 90, old + 90)
      expect(Tracks::BackfillScheduler.pop_range(user_id)).to eq([old - 90, old + 90])
      expect(Sidekiq.redis { _1.exists(range_key) }).to eq(0)
    end
  end

  it 'retains Redis behavior only when the shared table is absent' do
    travel_to now do
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute('DROP TABLE phoenix.track_backfill_ranges')
        PhoenixSchema.reset!
        Tracks::BackfillScheduler.new(user_id, [old]).call
        expect(Sidekiq.redis { _1.exists(range_key) }).to eq(1)
        expect(Tracks::BackfillScheduler.pop_range(user_id)).to eq([old, old])
        raise ActiveRecord::Rollback
      end
      PhoenixSchema.reset!
      allow(described_class).to receive(:accumulate).and_raise(ActiveRecord::StatementInvalid, 'injected SQL failure')
      expect { Tracks::BackfillScheduler.new(user_id, [old]).call }
        .to raise_error(ActiveRecord::StatementInvalid, 'injected SQL failure')
      expect(Sidekiq.redis { _1.exists(range_key) }).to eq(0)
    end
  end
end
