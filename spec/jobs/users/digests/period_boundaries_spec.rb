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
        user = create(:user, settings: { 'timezone' => 'Etc/UTC' })
        create(:stat, user:, year: 2024, month: 3, distance: 6968)
        klass = period == 'month' ? Users::Digests::Monthly::CalculatingJob : Users::Digests::Yearly::CalculatingJob
        job_owner!(klass::OWNER_KEY, :sidekiq, pinned: true)
        args = period == 'month' ? [user.id, 2024, 3] : [user.id, 2024]
        identity = ["digests.calculate_#{period}", user.id, 2024, period == 'month' ? 3 : 0]
        reader, writer = IO.pipe
        pid = nil
        begin
          ActiveRecord::Base.connection_handler.clear_all_connections!
          pid = fork do
            reader.close
            allow(Users::Digests::Execution).to receive(:write).and_wrap_original do |original, *values|
              key, state, outcome = values
              if state == 'generated'
                writer.puts('before_generated')
                writer.flush
                sleep
              end
              original.call(key, state, outcome)
            end
            klass.new(*args).perform_now
            exit! 4
          end
          writer.close
          expect(IO.select([reader], nil, nil, 10)).to be_truthy
          expect(reader.gets&.strip).to eq('before_generated')
          expect(user.digests).to be_empty
          Process.kill('KILL', pid)
          Process.wait(pid)
          pid = nil
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
          2.times { klass.new(*args).perform_now }
          expect(calls).to eq(period == 'month' ? 1 : 12)
          expect(user.digests.reload.count).to eq(1)
          expect(enqueued_jobs.count { |job| job[:job].name.include?('EmailSendingJob') }).to eq(1)
        ensure
          if pid
            Process.kill('KILL', pid)
            Process.wait(pid)
          end
          reader.close unless reader.closed?
          writer.close unless writer.closed?
          connection = ActiveRecord::Base.connection
          connection.execute("DELETE FROM phoenix.digest_executions WHERE user_id=#{user.id}")
          connection.execute("DELETE FROM phoenix.job_owners WHERE key=#{connection.quote(klass::OWNER_KEY)}")
          user.destroy!
        end
      end
    end
  end
end
