# frozen_string_literal: true

require 'rails_helper'
require 'open3'
require 'timeout'

RSpec.describe 'Users::Digests::Commands' do
  include ActiveSupport::Testing::TimeHelpers

  self.use_transactional_tests = false

  before do
    phoenix_tables!
    clear_digest_reverse_commands
  end

  after do
    clear_digest_command_fixtures
    clear_digest_reverse_commands
    JobOutbox.where(command_type: %w[digests.calculate_month digests.calculate_year]).delete_all
    ActiveRecord::Base.connection.execute(
      'DELETE FROM phoenix.job_owners WHERE key IN ' \
        "('command:digests.calculate_month', 'command:digests.calculate_year', " \
        "'cron:monthly_digest_scheduling_job', 'cron:yearly_digest_scheduling_job')"
    )
    ActiveRecord::Base.connection.execute('DROP SCHEMA IF EXISTS phoenix CASCADE')
    PhoenixTables.install_state!
  end

  def clear_digest_reverse_commands
    %w[rails_commands rails_commands_dead].each do |table|
      ActiveRecord::Base.connection.execute("DELETE FROM phoenix.#{table} WHERE kind LIKE 'digests.%'")
    end
  end

  def digest_command_user(**attributes)
    user = create(:user, **attributes)
    (@digest_command_user_ids ||= []) << user.id
    user
  end

  def clear_digest_command_fixtures
    ids = @digest_command_user_ids || []
    [Notification, Stat, Users::Digest].each { |model| model.where(user_id: ids).delete_all }
    User.unscoped.where(id: ids).delete_all
  end

  it 'command fixture cleanup removes its users and dependent rows while preserving unrelated rows' do
    unrelated = create(:user)
    user = digest_command_user
    stat = create(:stat, user:)
    digest = create(:users_digest, user:)
    clear_digest_command_fixtures
    expect(User.unscoped.exists?(user.id)).to be(false)
    expect(Stat.exists?(stat.id)).to be(false)
    expect(Users::Digest.exists?(digest.id)).to be(false)
    expect(User.unscoped.exists?(unrelated.id)).to be(true)
  ensure
    unrelated&.destroy!
  end

  def digest_reverse!(kind, payload)
    statement = 'INSERT INTO phoenix.rails_commands (kind, payload) VALUES (?, ?::jsonb)'
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([statement, kind, payload.to_json]))
  end

  it 'in-flight Rails and native digest workers converge in both writer orders ' \
     'and preserve metadata and terminal effects' do
    store = finish = rails_writer = nil
    original_config = ActiveRecord::Base.connection_db_config.configuration_hash
    shared_database = 'dawarich_phoenix_test_a12d1b2_scratch'
    expect(ENV.fetch('PHOENIX_TEST_DATABASE')).to eq('dawarich_phoenix_test_a12d1b2')
    command = %w[mix test test/dawarich/digests/job_lifecycle_test.exs
                 --include rails_parity --only rails_parity --seed 101]
    messages = Queue.new
    peer_output = +''
    peer_error = +''
    stdin, stdout, stderr, peer = Open3.popen3({ 'SELF_HOSTED' => 'false' }, *command,
                                               chdir: Rails.root.join('app-phoenix').to_s)
    reader = Thread.new do
      stdout.each_line do |line|
        peer_output << line
        messages << JSON.parse(line.delete_prefix('A12D1B2:')) if line.start_with?('A12D1B2:')
      end
      messages << { 'op' => 'eof' }
    end
    error_reader = Thread.new { peer_error << stderr.read }
    expect(collision_message(messages)).to eq('op' => 'ready', 'database' => shared_database)
    ActiveRecord::Base.establish_connection(original_config.merge(database: shared_database))
    cases = JSON.parse(Rails.root.join('app-phoenix/test/fixtures/a12d1b2/jobs.json').read).fetch('workers')

    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    travel_to Time.utc(2026, 10, 3, 12) do
      %w[monthly yearly].product(%w[rails_first native_first], %w[new existing]).each do |kind, order, profile|
        kase = cases.find { |row| row['id'] == "#{profile}_#{kind}_en" }
        collision_send(stdin, op: 'case', kind:, order:, profile:)
        expect(collision_message(messages)).to eq('op' => 'case_ready')
        load_collision_fixture(kase)
        type = kind == 'monthly' ? 'digests.calculate_month' : 'digests.calculate_year'
        job_owner!("command:#{type}", :sidekiq)
        rails_uuid = '00000000-0000-4000-8000-000000184001'
        allow(SecureRandom).to receive(:uuid).and_return(rails_uuid)
        ready = Queue.new
        store = Queue.new
        finish = Queue.new
        held = false
        allow_any_instance_of(Users::Digest).to receive(:save!).and_wrap_original do |save, *args, **opts|
          next save.call(*args, **opts) if held

          held = true
          ActiveRecord::Base.transaction do
            ready << { 'op' => 'rails_ready', 'pid' => ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()') }
            store.pop
            result = save.call(*args, **opts)
            if order == 'rails_first'
              ready << { 'op' => 'rails_stored' }
              finish.pop
            end
            result
          end
        end
        clear_enqueued_jobs
        calculator = kind == 'monthly' ? Users::Digests::Monthly::CalculatingJob : Users::Digests::Yearly::CalculatingJob
        mail = kind == 'monthly' ? Users::Digests::Monthly::EmailSendingJob : Users::Digests::Yearly::EmailSendingJob
        rails_writer = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Time.use_zone(kase.fetch('ambient_zone')) { calculator.perform_now(*kase.fetch('args')) }
          end
        end
        rails_ready = collision_message(ready)
        expect(rails_ready.fetch('op')).to eq('rails_ready')
        collision_send(stdin, op: 'start')
        native_ready = collision_message(messages)
        expect(native_ready.fetch('op')).to eq('native_ready')
        JobOwnership.release!("command:#{type}", by: 'mixed-runtime-spec')

        if order == 'rails_first'
          store << :store
          expect(collision_message(ready)).to eq('op' => 'rails_stored')
          collision_send(stdin, op: 'store')
          collision_blocked!(native_ready.fetch('pid'), rails_ready.fetch('pid'))
          finish << :finish
          expect(collision_message(messages).fetch('op')).to eq('native_stored')
        else
          collision_send(stdin, op: 'store')
          expect(collision_message(messages).fetch('op')).to eq('native_stored')
          store << :store
          collision_blocked!(rails_ready.fetch('pid'), native_ready.fetch('pid'))
        end
        collision_send(stdin, op: 'finish')
        expect(collision_message(messages)).to eq('op' => 'native_done')

        expect(rails_writer.join(5)).to eq(rails_writer)
        rails_writer.value
        expect(enqueued_jobs.count { |job| job[:job] == mail && job[:args] == kase['args'] }).to eq(1)
        actual = ActiveRecord::Base.connection.select_values(
          'SELECT row_to_json(d)::text FROM (SELECT * FROM public.digests WHERE user_id=14101) d'
        ).map { |row| JSON.parse(row) }.sole
        expected = kase.fetch('expected').fetch('rows').sole.except('id')
        expected['sharing_uuid'] = rails_uuid if profile == 'new' && order == 'rails_first'
        expect(actual.except('id')).to eq(expected), "#{kind}/#{order}/#{profile}"
        expect(Notification.where(user_id: 14_101)).to be_empty
        collision_send(stdin, op: 'verify', expected:)
        expect(collision_message(messages)).to eq('op' => 'verified')
        allow_any_instance_of(Users::Digest).to receive(:save!).and_call_original
        allow(SecureRandom).to receive(:uuid).and_call_original
      end
    end

    collision_send(stdin, op: 'stop')
    expect(collision_message(messages)).to eq('op' => 'done')
    stdin.close
    expect(peer.join(5)).to eq(peer)
    reader.join
    error_reader.join
    puts peer_output
    expect(peer.value.success?).to be(true), peer_output + peer_error
    expect(peer_output).to match(/3 tests, 0 failures, 2 excluded/)
  ensure
    store << :store if store
    finish << :finish if finish
    rails_writer&.kill if rails_writer&.alive?
    rails_writer&.join
    stdin&.close unless stdin&.closed?
    if peer && !peer.join(5)
      Process.kill('TERM', peer.pid)
      peer.join
    end
    reader&.join
    error_reader&.join
    puts peer_output if peer_output && $ERROR_INFO
    warn peer_error if peer_error.present? && $ERROR_INFO
    ActiveRecord::Base.establish_connection(original_config) if original_config
  end

  def collision_message(queue) = Timeout.timeout(5) { queue.pop }

  def collision_send(input, message)
    input.puts(JSON.generate(message))
    input.flush
  end

  def load_collision_fixture(kase)
    connection = ActiveRecord::Base.connection
    %w[users families family_memberships stats tracks track_segments points digests].each do |table|
      kase.fetch('input').fetch(table, []).each do |row|
        columns = row.keys.sort.map { |key| connection.quote_column_name(key) }.join(', ')
        connection.execute("INSERT INTO public.#{table} (#{columns}) SELECT #{columns} " \
                           "FROM json_populate_record(NULL::public.#{table}, #{connection.quote(row.to_json)}::json)")
      end
    end
    connection.execute("SELECT setval('public.digests_id_seq', 140500, false)")
    connection.execute("SELECT setval('public.stats_id_seq', 150500, false)")
  end

  def collision_blocked!(waiting, holding)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC)).to be < deadline
      blocked = ActiveRecord::Base.connection.select_value(
        "SELECT #{holding.to_i} = ANY(pg_blocking_pids(#{waiting.to_i}))"
      )
      break if blocked
    end
  end

  it 'digest rehome keeps failed and unsupported pending rows and preserves due time' do
    at = Time.utc(2030, 3, 29, 12, 34, 56)
    %w[month year].each do |period|
      type = "digests.calculate_#{period}"
      klass = period == 'month' ? Users::Digests::Monthly::CalculatingJob : Users::Digests::Yearly::CalculatingJob
      payload = { 'user_id' => 42, 'year' => 2025, 'time_zone' => 'Asia/Tokyo' }
      payload['month'] = 3 if period == 'month'
      args = period == 'month' ? [42, 2025, 3] : [42, 2025]
      attributes = { command_type: type, command_version: 1, aggregate_id: 42, payload:, scheduled_at: at }
      supported = JobOutbox.create!(**attributes, event_id: SecureRandom.uuid)
      unsupported = JobOutbox.create!(**attributes.merge(command_version: 2), event_id: SecureRandom.uuid)
      dispatched = JobOutbox.create!(**attributes, event_id: SecureRandom.uuid, state: 'dispatched')
      job_owner!("command:#{type}", :oban)
      clear_enqueued_jobs

      expect do
        expect(JobCommands.rehome!(type, by: 'digest-spec')).to eq(moved: 1, left: 0)
      end.to have_enqueued_job(klass).with(*args).at(at)
      expect(enqueued_jobs.sole['timezone']).to eq('Asia/Tokyo')
      expect(JobOutbox.exists?(supported.event_id)).to be(false)
      expect(unsupported.reload.state).to eq('pending')
      expect(dispatched.reload.state).to eq('dispatched')
      expect(ActiveRecord::Base.connection.select_rows(
               "SELECT owner, pinned FROM phoenix.job_owners WHERE key='command:#{type}'"
             )).to eq([['sidekiq', true]])

      failed = JobOutbox.create!(**attributes, event_id: SecureRandom.uuid)
      allow(klass).to receive(:set).and_raise(IOError, 'digest enqueue down')
      clear_enqueued_jobs
      expect(JobCommands.rehome!(type, by: 'digest-spec')).to eq(moved: 0, left: 1, error: 'IOError')
      expect(enqueued_jobs).to be_empty
      expect(failed.reload).to have_attributes(state: 'pending', scheduled_at: at, payload:)
      allow(klass).to receive(:set).and_call_original
    end
  end

  it 'a digest reverse calculation rechecks ownership and preserves run_at and timezone' do
    user = digest_command_user
    at = Time.utc(2030, 3, 29, 12, 34, 56)
    %w[month year].each do |period|
      type = "digests.calculate_#{period}"
      klass = period == 'month' ? Users::Digests::Monthly::CalculatingJob : Users::Digests::Yearly::CalculatingJob
      args = period == 'month' ? [user.id, 2025, 3] : [user.id, 2025]
      payload = { 'user_id' => user.id, 'year' => 2025, 'time_zone' => 'Asia/Tokyo', 'run_at' => at.to_i }
      payload['month'] = 3 if period == 'month'
      job_owner!("command:#{type}", :sidekiq)
      clear_enqueued_jobs
      digest_reverse!(type, payload)
      expect { RailsCommands::Poller.drain_once }.to have_enqueued_job(klass).with(*args).at(at)
      expect(enqueued_jobs.sole['timezone']).to eq('Asia/Tokyo')
      expect(JobOutbox.where(command_type: type)).to be_empty

      clear_enqueued_jobs
      digest_reverse!(type, payload)
      job_owner!("command:#{type}", :oban)
      expect { RailsCommands::Poller.drain_once }.not_to have_enqueued_job
      row = JobOutbox.where(command_type: type).sole
      expect(row.payload).to eq(payload.except('run_at'))
      expect(row.scheduled_at).to eq(at)
      expect(row.aggregate_id).to eq(user.id)

      deleted = digest_command_user(deleted_at: Time.current)
      [0, deleted.id].each do |id|
        digest_reverse!(type, payload.merge('user_id' => id))
        expect { RailsCommands::Poller.drain_once }.not_to have_enqueued_job
      end
      expect(JobOutbox.where(command_type: type).count).to eq(1)
    end
    expect(ActiveRecord::Base.connection.select_value(
             "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'digests.%'"
           )).to eq(0)
  end

  it 'digest email reverse commands enqueue the unchanged job with saved locale and source eligibility' do
    %w[month year].each do |period|
      klass = period == 'month' ? Users::Digests::Monthly::EmailSendingJob : Users::Digests::Yearly::EmailSendingJob
      action = period == 'month' ? :monthly_digest : :year_end_digest
      %w[enabled absent sent zero disabled deleted].each do |state|
        settings = { 'locale' => 'fr', "#{period}ly_digest_emails_enabled" => state != 'disabled' }
        user = digest_command_user(settings:)
        attributes = { user:, year: 2025, period_type: "#{period}ly", distance: state == 'zero' ? 0 : 500_000 }
        attributes[:month] = 3 if period == 'month'
        attributes[:sent_at] = Time.utc(2025, 4, 1) if state == 'sent'
        digest = create(:users_digest, **attributes) unless state == 'absent'
        user.update_column(:deleted_at, Time.current) if state == 'deleted'
        payload = { 'user_id' => user.id, 'year' => 2025, 'time_zone' => 'Asia/Tokyo' }
        payload['month'] = 3 if period == 'month'
        args = period == 'month' ? [user.id, 2025, 3] : [user.id, 2025]
        clear_enqueued_jobs
        digest_reverse!("digests.email_#{period}", payload)

        if state == 'deleted'
          expect { RailsCommands::Poller.drain_once }.not_to have_enqueued_job(klass)
        else
          expect { RailsCommands::Poller.drain_once }.to have_enqueued_job(klass).with(*args)
          job = enqueued_jobs.sole
          expect(job['locale']).to eq('fr')
          expect(job['timezone']).to eq('Asia/Tokyo')
          if state == 'enabled'
            expect { ActiveJob::Base.execute(job) }.to have_enqueued_mail(Users::DigestsMailer, action)
            expect(digest.reload.sent_at).to be_present
            expect(enqueued_jobs.last['locale']).to eq('fr')
            sent_at = digest.sent_at
            clear_enqueued_jobs
            digest_reverse!("digests.email_#{period}", payload)
            RailsCommands::Poller.drain_once
            expect { ActiveJob::Base.execute(enqueued_jobs.sole) }.not_to have_enqueued_mail
            expect(digest.reload.sent_at).to eq(sent_at)
          else
            before = digest&.sent_at
            expect { ActiveJob::Base.execute(job) }.not_to have_enqueued_mail
            expect(digest&.reload&.sent_at).to eq(before)
          end
        end
      end
      clear_enqueued_jobs
      digest_reverse!("digests.email_#{period}", { 'user_id' => 0, 'year' => 2025, 'month' => 3,
                                                 'time_zone' => 'Asia/Tokyo' })
      expect { RailsCommands::Poller.drain_once }.not_to have_enqueued_job
    end
    expect(ActiveRecord::Base.connection.select_value(
             "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'digests.%'"
           )).to eq(0)
  end

  it 'Rails digest schedulers stop under native cron ownership and keep their legacy scan otherwise' do
    user = digest_command_user(status: :active)
    create(:stat, user:, year: 2030, month: 2)
    create(:stat, user:, year: 2029, month: 1)
    allow(User).to receive(:active_or_trial).and_call_original
    schedulers = {
      'monthly' => [Users::Digests::Monthly::SchedulingJob, Users::Digests::Monthly::CalculatingJob,
                    [user.id, 2030, 2]],
      'yearly' => [Users::Digests::Yearly::SchedulingJob, Users::Digests::Yearly::CalculatingJob, [user.id, 2029]]
    }

    travel_to Time.zone.local(2030, 3, 2, 12) do
      schedulers.each do |period, (scheduler, _calculator, _args)|
        job_owner!("cron:#{period}_digest_scheduling_job", :oban)
        expect { scheduler.perform_now }.not_to have_enqueued_job
      end
      expect(User).not_to have_received(:active_or_trial)

      schedulers.each do |period, (scheduler, calculator, args)|
        key = "cron:#{period}_digest_scheduling_job"
        ActiveRecord::Base.connection.execute("DELETE FROM phoenix.job_owners WHERE key = '#{key}'")
        [nil, :sidekiq].each do |owner|
          job_owner!(key, owner) if owner
          clear_enqueued_jobs
          expect { scheduler.perform_now }.to have_enqueued_job(calculator).with(*args)
        end
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute('DROP TABLE phoenix.job_owners')
          expect { scheduler.perform_now }.to have_enqueued_job(calculator).with(*args)
          raise ActiveRecord::Rollback
        end

        type = period == 'monthly' ? 'digests.calculate_month' : 'digests.calculate_year'
        job_owner!("command:#{type}", :oban)
        clear_enqueued_jobs
        expect { scheduler.perform_now }.to have_enqueued_job(calculator).with(*args)
        expect(JobOutbox.where(command_type: type)).to be_empty
        calculator.perform_now(*args)
        expect(JobOutbox.where(command_type: type).sole.payload).to include('user_id' => user.id, 'year' => args[1])
      end
    end
  end

  it 'queued Rails digest calculations forward their stable ID and ambient zone once after claim' do
    user = digest_command_user
    allow(Stats::CalculateMonth).to receive(:new).and_return(instance_double(Stats::CalculateMonth, call: true))
    allow(Users::Digests::CalculateMonth).to receive(:new).and_return(
      instance_double(Users::Digests::CalculateMonth, call: true)
    )
    allow(Users::Digests::CalculateYear).to receive(:new).and_return(
      instance_double(Users::Digests::CalculateYear, call: true)
    )

    %w[month year].each do |period|
      type = "digests.calculate_#{period}"
      klass = period == 'month' ? Users::Digests::Monthly::CalculatingJob : Users::Digests::Yearly::CalculatingJob
      arguments = [user.id, '2025']
      arguments << '3' if period == 'month'
      payload = { 'user_id' => user.id, 'year' => 2025, 'time_zone' => 'Asia/Tokyo' }
      payload['month'] = 3 if period == 'month'
      job_owner!("command:#{type}", :oban)
      clear_enqueued_jobs
      job = Time.use_zone('Asia/Tokyo') { klass.new(*arguments) }
      Time.use_zone('Asia/Tokyo') { 2.times { job.perform_now } }

      row = JobOutbox.where(command_type: type).sole
      expect(row).to have_attributes(event_id: job.job_id, aggregate_id: user.id, command_version: 1, payload:)
      expect(row.metadata).to eq('producer' => klass.name)
      expect(enqueued_jobs).to be_empty
      expect(user.notifications).to be_empty
    end
    expect(Stats::CalculateMonth).not_to have_received(:new)
    expect(Users::Digests::CalculateMonth).not_to have_received(:new)
    expect(Users::Digests::CalculateYear).not_to have_received(:new)

    %w[month year].each do |period|
      type = "digests.calculate_#{period}"
      klass = period == 'month' ? Users::Digests::Monthly::CalculatingJob : Users::Digests::Yearly::CalculatingJob
      mail = period == 'month' ? Users::Digests::Monthly::EmailSendingJob : Users::Digests::Yearly::EmailSendingJob
      arguments = period == 'month' ? [user.id, 2025, 3] : [user.id, 2025]
      JobOutbox.where(command_type: type).delete_all
      ActiveRecord::Base.connection.execute("DELETE FROM phoenix.job_owners WHERE key = 'command:#{type}'")
      [nil, :sidekiq].each do |owner|
        job_owner!("command:#{type}", owner) if owner
        expect { klass.perform_now(*arguments) }.to have_enqueued_job(mail).with(*arguments)
        expect(JobOutbox.where(command_type: type)).to be_empty
      end
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute('DROP TABLE phoenix.job_owners')
        expect { klass.perform_now(*arguments) }.to have_enqueued_job(mail).with(*arguments)
        raise ActiveRecord::Rollback
      end
    end
  end

  it 'digest commands retain period timezone and due time on the Sidekiq path' do
    at = Time.utc(2030, 3, 29, 12, 34, 56)
    %w[month year].each do |period|
      type = "digests.calculate_#{period}"
      payload = { 'user_id' => 42, 'year' => 2025, 'time_zone' => 'Asia/Tokyo' }
      payload['month'] = 3 if period == 'month'
      arguments = period == 'month' ? [42, 2025, 3] : [42, 2025]
      klass = period == 'month' ? Users::Digests::Monthly::CalculatingJob : Users::Digests::Yearly::CalculatingJob

      [nil, :sidekiq].each do |owner|
        job_owner!("command:#{type}", owner) if owner
        clear_enqueued_jobs
        Time.use_zone('Europe/Berlin') do
          expect do
            expect(JobCommands.produce(type, payload, aggregate_id: 42, producer: 'spec', scheduled_at: at))
              .to eq(:sidekiq)
          end.to have_enqueued_job(klass).with(*arguments).at(at)
          expect(Time.zone.name).to eq('Europe/Berlin')
        end
        expect(enqueued_jobs.sole['timezone']).to eq('Asia/Tokyo')
        expect(JobOutbox.where(command_type: type)).to be_empty
        expect(JobCommands::COMMANDS.fetch(type).fetch(:version)).to eq(1)

        clear_enqueued_jobs
        ActiveRecord::Base.transaction do
          JobCommands.produce(type, payload, aggregate_id: 42, producer: 'spec', scheduled_at: at)
          expect(enqueued_jobs).to be_empty
          raise ActiveRecord::Rollback
        end
        expect(enqueued_jobs).to be_empty
        expect(JobOutbox.where(command_type: type)).to be_empty
      end
    end
  end
end
