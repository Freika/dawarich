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

    it 'oban? reports true only when Oban owns the key' do
      job_owner!(key, :oban)
      expect(described_class.oban?(key)).to be(true)

      job_owner!(key, :sidekiq)
      expect(described_class.oban?(key)).to be(false)
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

  context 'with the Lite archival cron and its mail key' do
    let(:lite_keys) { %w[command:mail.user.archival_approaching cron:lite_archival_warning_job] }

    def lite_rows
      ActiveRecord::Base.connection.select_rows(ActiveRecord::Base.sanitize_sql_array(
                                                  ['SELECT key, owner, pinned FROM phoenix.job_owners ' \
                                                   'WHERE key IN (?) ORDER BY key', lite_keys]
                                                ))
    end

    it 'never gives the two keys different owners: release and unpin move them together' do
      lite_keys.each do |released|
        lite_keys.each { |key| job_owner!(key, :oban) }

        expect(described_class.release!(released, by: 'spec')).to match_array(lite_keys)
        expect(lite_rows).to eq(lite_keys.map { |key| [key, 'sidekiq', true] }), released

        expect(described_class.unpin!(released, by: 'spec')).to match_array(lite_keys)
        expect(lite_rows).to eq(lite_keys.map { |key| [key, 'sidekiq', false] }), released
      end
    end
  end

  describe 'the lock protocol' do
    self.use_transactional_tests = false

    after do
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '2s'")
        ActiveRecord::Base.connection.execute('DROP SCHEMA IF EXISTS phoenix CASCADE')
      end
    end

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

      begin
        holding.pop

        expect do
          ActiveRecord::Base.transaction do
            ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '50ms'")
            ActiveRecord::Base.connection.execute("UPDATE phoenix.job_owners SET owner = 'oban' WHERE key = '#{key}'")
          end
        end.to raise_error(ActiveRecord::LockWaitTimeout)
      ensure
        release << true
        raise 'holder thread did not finish: still holding the row lock' unless holder.join(5)
      end

      expect(holder.value).to eq(:effect_done)
      described_class.put!(key, :oban, pinned: false, by: 'spec')
      expect(described_class.with_owner(key) { :late }).to eq(:not_owner)
    end

    it 'gives up on an owner change after a bounded wait behind a transaction that holds the row' do
      stub_const('JobOwnership::LOCK_TIMEOUT', '100ms')
      job_owner!(key, :oban)
      holding = Queue.new
      release = Queue.new

      holder = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ActiveRecord::Base.transaction do
            described_class.lock_owner(key)
            holding << true
            release.pop
          end
        end
      end

      attempt = nil
      begin
        Timeout.timeout(5) { holding.pop }
        attempt = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            %i[release! unpin!].map do |change|
              described_class.public_send(change, key, by: 'spec')
              :changed
            rescue ActiveRecord::LockWaitTimeout
              :gave_up
            end
          end
        end

        expect(attempt.join(3)&.value).to eq(%i[gave_up gave_up])
      ensure
        release << true
        raise 'holder thread did not finish: still holding the row lock' unless holder.join(5)
        raise 'owner change did not finish after the holder released the row' unless attempt.nil? || attempt.join(5)
      end

      expect(described_class.lock_owner(key)).to eq(:oban)
    end
  end
end
