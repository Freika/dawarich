# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Single digest period execution', type: :job do
  %w[month year].each do |period|
    context period do
      let(:effect) { "digests.calculate_#{period}" }
      let(:klass) { period == 'month' ? Users::Digests::Monthly::CalculatingJob : Users::Digests::Yearly::CalculatingJob }
      let!(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC' }) }
      let!(:stat) { create(:stat, user:, year: 2024, month: 3) }
      let(:args) { period == 'month' ? [user.id, 2024, 3] : [user.id, 2024] }
      let(:month) { period == 'month' ? 3 : 0 }

      before do
        job_owner!(klass::OWNER_KEY, :sidekiq, pinned: true)
        @calls = 0
        allow_any_instance_of(Stats::CalculateMonth).to receive(:call).and_wrap_original do |original|
          @calls += 1
          original.call
        end
      end

      %w[absent claimed generated published].each do |initial|
        it "RX15 #{period} Rails resumes #{initial} from the single period record" do
          seed(initial) unless initial == 'absent'
          klass.new(*args).perform_now
          klass.new(*args).perform_now
          expect(@calls).to eq(if %w[absent claimed].include?(initial)
                                 period == 'month' ? 1 : 12
                               else
                                 0
                               end)
          expect(saved_state).to eq('published')
        end
      end

      it "RX16 #{period} Rails publication failure preserves generation for retry" do
        allow(Users::Digests::Commands).to receive(:publish_email).and_wrap_original do |original, *args, **options|
          original.call(*args, **options)
          raise IOError, 'publication fault'
        end
        klass.new(*args).perform_now
        expect(saved_state).to eq('generated')
        expect(Notification.where(user: user, kind: :error).count).to eq(1)
        expect(enqueued_jobs).to be_empty
        expect(ActiveRecord::Base.connection.select_value(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE kind='digests.email_#{period}'"
               )).to eq(0)
        expect(@calls).to eq(period == 'month' ? 1 : 12)
        allow(Users::Digests::Commands).to receive(:publish_email).and_call_original
        klass.new(*args).perform_now
        expect(@calls).to eq(period == 'month' ? 1 : 12)
        expect(saved_state).to eq('published')
      end

      it "RX17 #{period} Rails generation failure releases the claim" do
        allow_any_instance_of(period == 'month' ? Users::Digests::CalculateMonth : Users::Digests::CalculateYear)
          .to receive(:call).and_raise(IOError, 'generation fault')
        klass.new(*args).perform_now
        expect(saved_state).to be_nil
        expect(user.digests).to be_empty
        RSpec::Mocks.space.proxy_for(Users::Digests::Commands).reset
        allow_any_instance_of(period == 'month' ? Users::Digests::CalculateMonth : Users::Digests::CalculateYear)
          .to receive(:call).and_call_original
        klass.new(*args).perform_now
        expect(saved_state).to eq('published')
      end

      it "RX19 #{period} Rails missing user records completion without mail" do
        missing_args = args.dup
        missing_args[0] = 2_100_000_000
        klass.new(*missing_args).perform_now
        sql = ActiveRecord::Base.sanitize_sql_array([
                                                      'SELECT state FROM phoenix.digest_executions ' \
          'WHERE effect=? AND user_id=? AND year=2024 AND month=?',
                                                      effect, missing_args[0], month
                                                    ])
        value = ActiveRecord::Base.connection.select_value(sql)
        expect(value).to eq('published')
        expect(@calls).to eq(0)
        expect(enqueued_jobs).to be_empty
      end

      %w[terminal shared].each do |legacy|
        it "RX20 #{period} Rails adopts legacy #{legacy} under the period lock" do
          receipt = SecureRandom.uuid
          marker = if legacy == 'terminal'
                     receipt
                   else
                     Stats::EffectReceipts.id(
                       receipt, effect.sub('calculate_', 'generate_'), nil, nil
                     )
                   end
          handler = legacy == 'terminal' ? effect : "#{effect.sub('calculate_', 'generate_')}:mail"
          text = 'INSERT INTO phoenix.processed_commands(event_id,handler,processed_at) VALUES(?,?,now())'
          sql = ActiveRecord::Base.sanitize_sql_array([text, marker, handler])
          ActiveRecord::Base.connection.execute(sql)
          klass.new(*args, execution_receipt: receipt).perform_now
          expect(@calls).to eq(0)
          expect(saved_state).to eq('published')
          expect(enqueued_jobs.size).to eq(legacy == 'terminal' ? 0 : 1)
        end
      end

      it "RX21 #{period} upgrade imports sent digest as published without generation or mail" do
        create(:users_digest, user:, year: 2024, month: month.zero? ? nil : month,
                              period_type: period == 'month' ? :monthly : :yearly, sent_at: Time.current)
        sql = Rails.root.join('app-phoenix/priv/repo/sql/20261007180000_digest_executions_backfill.sql').read
        ActiveRecord::Base.connection.execute(sql)
        ActiveRecord::Base.connection.execute(sql)
        klass.new(*args).perform_now
        expect(@calls).to eq(0)
        expect(saved_state).to eq('published')
        expect(enqueued_jobs).to be_empty
      end

      it "RX26 #{period} upgrade imports retained mail admission without another email intent" do
        create(:users_digest, user:, year: 2024, month: month.zero? ? nil : month,
                              period_type: period == 'month' ? :monthly : :yearly)
        payload = { user_id: user.id, year: 2024, time_zone: 'Etc/UTC' }
        payload[:month] = month unless month.zero?
        text = 'INSERT INTO phoenix.rails_commands(kind,payload) VALUES(?,?::jsonb)'
        sql = ActiveRecord::Base.sanitize_sql_array([text, "digests.email_#{period}", JSON.generate(payload)])
        ActiveRecord::Base.connection.execute(sql)
        ActiveRecord::Base.connection.execute(
          Rails.root.join('app-phoenix/priv/repo/sql/20261007180000_digest_executions_backfill.sql').read
        )
        klass.new(*args).perform_now
        expect(@calls).to eq(0)
        expect(saved_state).to eq('published')
        expect(enqueued_jobs).to be_empty
      end

      def seed(state)
        return unless PhoenixSchema.table?('digest_executions')

        text = 'INSERT INTO phoenix.digest_executions(effect,user_id,year,month,state,outcome) VALUES(?,?,2024,?,?,?)'
        sql = ActiveRecord::Base.sanitize_sql_array([text, effect, user.id, month, state, 'mail'])
        ActiveRecord::Base.connection.execute(sql)
      end

      def saved_state
        return unless PhoenixSchema.table?('digest_executions')

        text = 'SELECT state FROM phoenix.digest_executions WHERE effect=? AND user_id=? AND year=2024 AND month=?'
        sql = ActiveRecord::Base.sanitize_sql_array([text, effect, user.id, month])
        ActiveRecord::Base.connection.select_value(sql)
      end
    end
  end
end
