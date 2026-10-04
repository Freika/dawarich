# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::Digests::Commands' do
  self.use_transactional_tests = false

  before { phoenix_tables! }

  after do
    JobOutbox.where(command_type: %w[digests.calculate_month digests.calculate_year]).delete_all
    ActiveRecord::Base.connection.execute(
      'DELETE FROM phoenix.job_owners WHERE key IN ' \
        "('command:digests.calculate_month', 'command:digests.calculate_year')"
    )
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
