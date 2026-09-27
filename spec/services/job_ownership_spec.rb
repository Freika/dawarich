# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JobOwnership do
  let(:key) { 'command:trips.calculate' }

  context 'when Phoenix has never migrated the database' do
    it 'runs the block as Sidekiq without aborting the caller transaction' do
      ActiveRecord::Base.transaction do
        expect(described_class.with_owner(key) { :ran }).to eq(:ran)
        expect(described_class.lock_owner(key)).to eq(:sidekiq)
        expect(ActiveRecord::Base.connection.select_value('SELECT 1')).to eq(1)
      end
    end

    it 'refuses to release a key it cannot record' do
      expect { described_class.release!(key, by: 'spec') }.to raise_error(/phoenix\.job_owners does not exist/)
    end
  end

  context 'when the phoenix tables exist' do
    it 'treats a missing row as Sidekiq' do
      phoenix_tables!

      expect(described_class.with_owner(key) { :ran }).to eq(:ran)
    end

    it 'skips and logs when Oban owns the key' do
      job_owner!(key, :oban)
      allow(Rails.logger).to receive(:info).and_call_original

      expect(described_class.with_owner(key) { :ran }).to eq(:not_owner)
      expect(Rails.logger).to have_received(:info).with("JobOwnership: #{key} owned by oban, skipped")
      expect(described_class.with_owner(key, :oban) { :ran }).to eq(:ran)
    end

    it 'releases to a pinned Sidekiq owner and unpins' do
      job_owner!(key, :oban)

      described_class.release!(key, by: 'spec')
      expect(ActiveRecord::Base.connection.select_rows(
               "SELECT owner, pinned, updated_by FROM phoenix.job_owners WHERE key = '#{key}'"
             )).to eq([['sidekiq', true, 'spec']])

      described_class.unpin!(key, by: 'spec')
      expect(ActiveRecord::Base.connection.select_value(
               "SELECT pinned FROM phoenix.job_owners WHERE key = '#{key}'"
             )).to be(false)
    end
  end

  describe 'the lock protocol' do
    self.use_transactional_tests = false

    after { ActiveRecord::Base.connection.execute('DROP SCHEMA IF EXISTS phoenix CASCADE') }

    it 'makes an owner change wait for a gate that holds the row' do
      phoenix_tables!
      job_owner!(key, :sidekiq)
      holding = Queue.new
      release = Queue.new

      holder = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.with_owner(key) do
            holding << true
            release.pop
            :effect_done
          end
        end
      end
      holding.pop

      expect do
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '50ms'")
          ActiveRecord::Base.connection.execute("UPDATE phoenix.job_owners SET owner = 'oban' WHERE key = '#{key}'")
        end
      end.to raise_error(ActiveRecord::LockWaitTimeout)

      release << true
      expect(holder.value).to eq(:effect_done)
      described_class.put!(key, :oban, pinned: false, by: 'spec')
      expect(described_class.with_owner(key) { :late }).to eq(:not_owner)
    end
  end
end
