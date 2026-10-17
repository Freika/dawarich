# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Digest period boundaries', type: :job do
  %w[month year].each do |period|
    context period do
      let(:effect) { "digests.calculate_#{period}" }
      let(:klass) { period == 'month' ? Users::Digests::Monthly::CalculatingJob : Users::Digests::Yearly::CalculatingJob }
      let!(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC' }) }
      let!(:stat) { create(:stat, user:, year: 2024, month: 3) }
      let(:args) { period == 'month' ? [user.id, 2024, 3] : [user.id, 2024] }
      let(:identity) { [effect, user.id, 2024, period == 'month' ? 3 : 0] }

      before do
        job_owner!(klass::OWNER_KEY, :sidekiq, pinned: true)
        @calls = 0
        allow_any_instance_of(Stats::CalculateMonth).to receive(:call).and_wrap_original do |original|
          @calls += 1
          original.call
        end
      end

      it "RX37 #{period} Rails resumes persisted generated missing with an existing user" do
        execute('INSERT INTO phoenix.digest_executions(effect,user_id,year,month,state,outcome) ' \
                "VALUES(?,?,?,?,'generated','missing')", *identity)
        2.times { klass.new(*args).perform_now }
        expect(saved).to include('state' => 'published', 'outcome' => 'missing')
        expect(@calls).to eq(0)
        expect(user.digests).to be_empty
        expect(enqueued_jobs).to be_empty
      end

      it "RX38 #{period} Rails adopts a raw source-job terminal before generation" do
        job = klass.new(*args)
        execute('INSERT INTO phoenix.processed_commands(event_id,handler,processed_at) VALUES(?,?,now())',
                job.job_id, effect)
        job.perform_now
        expect(saved).to include('state' => 'published')
        expect(@calls).to eq(0)
        expect(user.digests).to be_empty
        expect(enqueued_jobs).to be_empty
      end

      it "RX39 #{period} Rails adopts a shared missing marker with an existing user" do
        receipt = SecureRandom.uuid
        generation = effect.sub('calculate_', 'generate_')
        marker = Stats::EffectReceipts.id(receipt, generation, nil, nil)
        execute('INSERT INTO phoenix.processed_commands(event_id,handler,processed_at) VALUES(?,?,now())',
                marker, "#{generation}:missing")
        klass.new(*args, execution_receipt: receipt).perform_now
        expect(saved).to include('state' => 'published', 'outcome' => 'missing')
        expect(@calls).to eq(0)
        expect(user.digests).to be_empty
        expect(enqueued_jobs).to be_empty
      end

      it "RX40 #{period} Rails alone generates and mails when the period table is absent" do
        execute('ALTER TABLE phoenix.digest_executions RENAME TO hidden_digest_executions')
        PhoenixSchema.reset!
        begin
          klass.new(*args).perform_now
          expect(@calls).to eq(period == 'month' ? 1 : 12)
          expect(user.digests.count).to eq(1)
          expect(enqueued_jobs.count { |job| job[:job].name.include?('EmailSendingJob') }).to eq(1)
        ensure
          execute('ALTER TABLE phoenix.hidden_digest_executions RENAME TO digest_executions')
          PhoenixSchema.reset!
        end
      end

      it "RX41 #{period} historical calculation classes remain usable with the additive period table" do
        expect(PhoenixSchema.table?('digest_executions')).to be(true)
        calculator = period == 'month' ? Users::Digests::CalculateMonth : Users::Digests::CalculateYear
        calculator.new(*args).call
        expect(user.digests.count).to eq(1)
        expect(saved).to be_nil
        expect(enqueued_jobs).to be_empty
      end

      def execute(sql, *binds)
        ActiveRecord::Base.connection.exec_query(ActiveRecord::Base.sanitize_sql_array([sql, *binds]))
      end

      def saved
        execute('SELECT state,outcome FROM phoenix.digest_executions ' \
                'WHERE effect=? AND user_id=? AND year=? AND month=?',
                *identity).first
      end
    end
  end

  context 'owned worker crash' do
    self.use_transactional_tests = false

    %w[month year].each do |period|
      it "RX42 #{period} Rails crash after result before generated rolls back result and claim" do
        with_crash_fixture(period) do |user, klass, args, identity, receipt|
          with_crash_worker(klass, args, receipt) do
            expect(user.digests).to be_empty
          end
          connection = ActiveRecord::Base.connection
          ActiveRecord::Base.transaction do
            connection.execute("SET LOCAL statement_timeout='5s'")
            lock_sql = ['SELECT pg_advisory_xact_lock(hashtextextended(?,0))', JSON.generate(identity)]
            connection.execute(ActiveRecord::Base.sanitize_sql_array(lock_sql))
            expect(user.digests.reload).to be_empty
            expect(connection.select_value("SELECT count(*) FROM phoenix.digest_executions WHERE user_id=#{user.id}"))
              .to eq(0)
          end
          calls = 0
          allow_any_instance_of(Stats::CalculateMonth).to receive(:call).and_wrap_original do |original|
            calls += 1
            original.call
          end
          2.times { klass.new(*args, execution_receipt: receipt).perform_now }
          expect(calls).to eq(period == 'month' ? 1 : 12)
          expect(user.digests.reload.count).to eq(1)
          expect(enqueued_jobs.count { |job| job[:job].name.include?('EmailSendingJob') }).to eq(1)
        end
      end
    end

    it 'RX43 failed crash probes remove committed fixtures while preserving unrelated rows' do
      with_crash_fixture('month') do
        connection = ActiveRecord::Base.connection
        before_ids = [User.unscoped.order(:id).pluck(:id), Stat.order(:id).pluck(:id)]
        owner = connection.select_all('SELECT * FROM phoenix.job_owners').to_a
        %w[month year].each do |period|
          expect do
            with_crash_fixture(period) do |_user, worker, worker_args, _key, receipt|
              allow_any_instance_of(worker).to receive(:perform_now) { exit! 4 }
              with_crash_worker(worker, worker_args, receipt) { raise 'unexpected boundary' }
            end
          end.to raise_error(IOError, /exitstatus=4/)
        end
        expect(User.unscoped.order(:id).pluck(:id)).to eq(before_ids[0])
        expect(Stat.order(:id).pluck(:id)).to eq(before_ids[1])
        expect(connection.select_all('SELECT * FROM phoenix.job_owners').to_a).to eq(owner)
      end
    end

    it 'RX44 forked crash workers bypass GSS credential discovery without changing parent connection settings' do
      parent_config = ActiveRecord::Base.connection_db_config.configuration_hash
      parent_gss = ENV['PGGSSENCMODE']
      %w[month year].each do |period|
        with_crash_fixture(period) do |_user, klass, args, _identity, receipt|
          allow_any_instance_of(klass).to receive(:perform_now).and_wrap_original do |original|
            options = ActiveRecord::Base.connection.raw_connection.conninfo
            mode = options.find { _1[:keyword] == 'gssencmode' }.fetch(:val)
            raise IOError, 'forked connection attempted GSS discovery' unless mode == 'disable'

            original.call
          end
          expect { with_crash_worker(klass, args, receipt) {} }.not_to raise_error
        end
      end
      expect(ActiveRecord::Base.connection_db_config.configuration_hash == parent_config).to be(true)
      expect(ENV['PGGSSENCMODE']).to eq(parent_gss)
    end

    def with_crash_fixture(period)
      klass = period == 'month' ? Users::Digests::Monthly::CalculatingJob : Users::Digests::Yearly::CalculatingJob
      connection = ActiveRecord::Base.connection
      key = connection.quote(klass::OWNER_KEY)
      previous_owner = connection.select_all("SELECT * FROM phoenix.job_owners WHERE key=#{key}").first
      user = create(:user, settings: { 'timezone' => 'Etc/UTC' })
      create(:stat, user:, year: 2024, month: 3, distance: 6968)
      job_owner!(klass::OWNER_KEY, :sidekiq, pinned: true)
      args = period == 'month' ? [user.id, 2024, 3] : [user.id, 2024]
      identity = ["digests.calculate_#{period}", user.id, 2024, period == 'month' ? 3 : 0]
      receipt = SecureRandom.uuid
      yield user, klass, args, identity, receipt
    ensure
      connection = ActiveRecord::Base.connection
      if user
        connection.execute("DELETE FROM phoenix.digest_executions WHERE user_id=#{user.id}")
        if receipt
          generation = identity.first.sub('calculate_', 'generate_')
          marker = Stats::EffectReceipts.id(receipt, generation, nil, nil)
          sql = ['DELETE FROM phoenix.processed_commands WHERE event_id IN (?,?)', receipt, marker]
          connection.execute(ActiveRecord::Base.sanitize_sql_array(sql))
        end
        user.stats.delete_all
        user.digests.delete_all
        user.notifications.delete_all
        user.delete
      end
      connection.execute("DELETE FROM phoenix.job_owners WHERE key=#{key}")
      if previous_owner
        fields = previous_owner.keys.map { connection.quote_column_name(_1) }.join(',')
        values = previous_owner.values.map { connection.quote(_1) }.join(',')
        connection.execute("INSERT INTO phoenix.job_owners (#{fields}) VALUES (#{values})")
      end
    end

    def with_crash_worker(klass, args, receipt)
      reader, writer = IO.pipe
      pid = nil
      child_config = ActiveRecord::Base.connection_db_config.configuration_hash
      ActiveRecord::Base.connection_handler.clear_all_connections!
      pid = fork do
        reader.close
        ActiveRecord::Base.establish_connection(child_config.merge(gssencmode: 'disable'))
        states = []
        allow(Users::Digests::Execution).to receive(:write).and_wrap_original do |original, *values|
          key, state, outcome = values
          states << [state, outcome]
          if state == 'generated'
            writer.puts(JSON.generate(event: 'before_generated', states: states))
            writer.flush
            sleep
          end
          original.call(key, state, outcome)
        end
        begin
          klass.new(*args, execution_receipt: receipt).perform_now
          writer.puts(JSON.generate(event: 'finished', states: states))
        rescue StandardError => e
          writer.puts(JSON.generate(event: 'error', error: e.class.name, states: states))
        end
        writer.flush
        exit! 4
      end
      writer.close
      raise IOError, 'worker did not report a boundary' unless IO.select([reader], nil, nil, 10)

      message = reader.gets
      event = JSON.parse(message) if message
      unless event && event['event'] == 'before_generated'
        _, status = Process.wait2(pid)
        pid = nil
        raise IOError, "worker exited before generated: #{event.inspect}; " \
                       "exitstatus=#{status.exitstatus}, termsig=#{status.termsig}"
      end
      yield
    ensure
      if pid && !Process.waitpid(pid, Process::WNOHANG)
        begin
          Process.kill('KILL', pid)
        rescue Errno::ESRCH
          nil
        end
        Process.wait(pid)
      end
      reader&.close unless reader&.closed?
      writer&.close unless writer&.closed?
    end
  end
end
