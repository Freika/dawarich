# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JobOwnership do
  let(:key) { 'command:trips.calculate' }

  context 'when Phoenix has never migrated the database' do
    before do
      ActiveRecord::Base.connection.execute('DROP TABLE IF EXISTS phoenix.job_owners')
      PhoenixSchema.reset!
    end

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

  context 'with the shared geocoding rate limiter guard' do
    let(:geocoding_key) { 'command:visits.suggest' }

    def stub_shared_limiter_flag(value)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('GEOCODING_SHARED_RATE_LIMIT').and_return(value)
    end

    it 'refuses a geocoding key to Oban while the shared limiter is off' do
      phoenix_tables!
      stub_shared_limiter_flag(nil)

      expect do
        described_class.put!(geocoding_key, :oban, pinned: false, by: 'spec')
      end.to raise_error(ArgumentError, /GEOCODING_SHARED_RATE_LIMIT/)
      expect(described_class.lock_owner(geocoding_key)).to eq(:sidekiq)

      expect(described_class.put!(key, :oban, pinned: false, by: 'spec')).to eq([key])
      expect(described_class.release!(geocoding_key, by: 'spec')).to eq([geocoding_key])
    end

    it 'gives a geocoding key to Oban once the flag is on' do
      phoenix_tables!
      stub_shared_limiter_flag('true')

      described_class.put!(geocoding_key, :oban, pinned: false, by: 'spec')

      expect(described_class.lock_owner(geocoding_key)).to eq(:oban)
    end
  end

  it 'source cron publication batches stop after a native flip at a user boundary' do
    users = create_list(:user, 2, status: :active,
                                  settings: { 'monthly_digest_emails_enabled' => true,
                                              'yearly_digest_emails_enabled' => true })
    users.each do |user|
      create(:stat, user:, year: 1.month.ago.year, month: 1.month.ago.month)
      create(:stat, user:, year: 1.year.ago.year, month: 1)
    end
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
    [
      [Points::RawData::ArchiveJob, Points::RawData::ArchiveUserJob, 'cron:raw_data_archive_job'],
      [Points::RawData::ClearJob, Points::RawData::ClearUserJob, 'cron:raw_data_clear_job'],
      [Users::Digests::Monthly::SchedulingJob, Users::Digests::Monthly::CalculatingJob,
       'cron:monthly_digest_scheduling_job'],
      [Users::Digests::Yearly::SchedulingJob, Users::Digests::Yearly::CalculatingJob,
       'cron:yearly_digest_scheduling_job']
    ].each do |parent, child, owner_key|
      job_owner!(owner_key, :sidekiq)
      published = []
      allow(child).to receive(:perform_later) do |*arguments|
        published << arguments
        JobOwnership.put!(owner_key, :oban, pinned: false, by: 'spec')
        true
      end
      parent.perform_now
      expect(published.size).to eq(1), parent.name
    end

    job_owner!('cron:bulk_stats_calculating_job', :sidekiq)
    published = []
    allow(Stats::BulkCalculator).to receive(:new) do |user_id|
      calculator = instance_double(Stats::BulkCalculator)
      allow(calculator).to receive(:call) do
        published << user_id
        JobOwnership.put!('cron:bulk_stats_calculating_job', :oban, pinned: false, by: 'spec')
      end
      calculator
    end
    BulkStatsCalculatingJob.perform_now
    expect(published.size).to eq(1), 'BulkStatsCalculatingJob'

    job_owner!('cron:raw_data_verify_job', :sidekiq)
    2.times { |index| create(:points_raw_data_archive, user: users.first, chunk_number: index + 1) }
    verifier = instance_double(Points::RawData::Verifier)
    allow(Points::RawData::Verifier).to receive(:new).and_return(verifier)
    verified = []
    allow(verifier).to receive(:verify_specific_archive) do |archive_id|
      verified << archive_id
      JobOwnership.put!('cron:raw_data_verify_job', :oban, pinned: false, by: 'spec')
    end
    Points::RawData::VerifyRandomJob.perform_now
    expect(verified.size).to eq(1), 'Points::RawData::VerifyRandomJob'
  end

  it 'source watcher recovery and retention recheck ownership between individual effects' do
    user = create(:user)
    job_owner!('cron:watcher_job', :sidekiq)
    watcher = Imports::Watcher.new
    allow(Imports::Watcher).to receive(:new).and_return(watcher)
    allow(watcher).to receive(:user_directories).and_return([user.email])
    allow(watcher).to receive(:file_names).and_return(%w[first.gpx second.gpx])
    published = []
    allow(watcher).to receive(:create_import) do |_, _, filename|
      published << filename
      JobOwnership.put!('cron:watcher_job', :oban, pinned: false, by: 'spec')
    end
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    Import::WatcherJob.perform_now
    expect(published).to eq(['first.gpx'])

    job_owner!('cron:stale_jobs_recovery_job', :sidekiq)
    exports = create_list(:export, 2, user:, status: :processing, start_at: 1.week.ago, end_at: Time.current)
    exports.each { |export| export.update_column(:processing_started_at, 3.hours.ago) }
    allow_any_instance_of(Notifications::Create).to receive(:call).and_wrap_original do |original|
      original.call
      JobOwnership.put!('cron:stale_jobs_recovery_job', :oban, pinned: false, by: 'spec')
    end
    StaleJobsRecoveryJob.perform_now
    expect(exports.map { |export| export.reload.status }).to eq(%w[failed processing])

    job_owner!('cron:route_videos_purge_job', :sidekiq)
    allow(DawarichSettings).to receive_messages(video_retention_days: 30, video_max_per_user: 0)
    videos = create_list(:route_video, 2, :with_file, user:, created_at: 31.days.ago)
    allow_any_instance_of(RouteVideo).to receive(:expire!).and_wrap_original do |original|
      original.call
      JobOwnership.put!('cron:route_videos_purge_job', :oban, pinned: false, by: 'spec')
    end
    RouteVideos::PurgeJob.perform_now
    expect(videos.map { |video| video.reload.status }).to eq(%w[expired stored])
  end

  describe 'the lock protocol' do
    self.use_transactional_tests = false

    after do
      PhoenixTables.clear!
    end

    it 'fences a first source effect against the first native claim when the owner row is absent' do
      phoenix_tables!
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
        Timeout.timeout(5) { holding.pop }
        stub_const('JobOwnership::LOCK_TIMEOUT', '50ms')
        expect { described_class.put!(key, :oban, pinned: false, by: 'spec') }
          .to raise_error(ActiveRecord::LockWaitTimeout)
      ensure
        release << true
        raise 'source effect still holds its lock' unless holder.join(5)
      end

      expect(holder.value).to eq(:effect_done)
      described_class.put!(key, :oban, pinned: false, by: 'spec')
      expect(described_class.with_owner(key) { :late }).to eq(:not_owner)
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
