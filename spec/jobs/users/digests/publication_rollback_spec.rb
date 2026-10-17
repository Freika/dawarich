# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Digest publication transaction rollback', type: :job do
  %w[month year].each do |period|
    it "RX43 #{period} rollback at the existing publication savepoint preserves generated and remains retryable" do
      user = create(:user, settings: { 'timezone' => 'Etc/UTC' })
      create(:stat, user:, year: 2024, month: 3, distance: 6968)
      klass = period == 'month' ? Users::Digests::Monthly::CalculatingJob : Users::Digests::Yearly::CalculatingJob
      job_owner!(klass::OWNER_KEY, :sidekiq, pinned: true)
      args = period == 'month' ? [user.id, 2024, 3] : [user.id, 2024]
      receipt = SecureRandom.uuid
      calls = 0
      injections = 0
      allow_any_instance_of(Stats::CalculateMonth).to receive(:call).and_wrap_original do |original|
        calls += 1
        original.call
      end
      source = Rails.root.join('app/services/users/digests/execution.rb')
      publication_line = source.readlines.index { |line| line.include?('ActiveRecord::Base.transaction') } + 1
      allow(ActiveRecord::Base).to receive(:transaction).and_wrap_original do |original, *values, **options, &block|
        at_publication = caller_locations.any? do |frame|
          frame.path == source.to_s && frame.lineno == publication_line
        end
        original.call(*values, **options) do
          result = block.call
          if at_publication
            injections += 1
            raise ActiveRecord::Rollback
          end
          result
        end
      end

      escaped = nil
      begin
        klass.new(*args, execution_receipt: receipt).perform_now
      rescue StandardError => e
        escaped = e
      end
      connection = ActiveRecord::Base.connection
      read = lambda do
        sql = ActiveRecord::Base.sanitize_sql_array([
                                                      'SELECT state,outcome FROM phoenix.digest_executions ' \
          'WHERE effect=? AND user_id=? AND year=2024 AND month=?',
                                                      "digests.calculate_#{period}", user.id, period == 'month' ? 3 : 0
                                                    ])
        connection.exec_query(sql).first
      end
      failed_state = read.call
      failed_mail = enqueued_jobs.size
      failed_admissions = connection.select_value('SELECT count(*) FROM phoenix.rails_commands')
      terminal_sql = ActiveRecord::Base.sanitize_sql_array(
        ['SELECT count(*) FROM phoenix.processed_commands WHERE event_id=?', receipt]
      )
      failed_terminal = connection.select_value(terminal_sql)
      allow(ActiveRecord::Base).to receive(:transaction).and_call_original
      2.times { klass.new(*args, execution_receipt: receipt).perform_now }

      aggregate_failures do
        expect(injections).to eq(1)
        expect(failed_state).to include('state' => 'generated', 'outcome' => 'mail')
        expect(failed_mail).to eq(0)
        expect(failed_admissions).to eq(0)
        expect(failed_terminal).to eq(0)
        expect(escaped).to be_a(IOError)
        expect(read.call).to include('state' => 'published', 'outcome' => 'mail')
        expect(enqueued_jobs.size).to eq(1)
        expect(connection.select_value(terminal_sql)).to eq(1)
        expect(user.digests.count).to eq(1)
        expect(calls).to eq(period == 'month' ? 1 : 12)
      end
    end
  end
end
