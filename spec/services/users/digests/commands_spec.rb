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

  it 'queued Rails digest calculations forward their stable ID and ambient zone once after claim' do
    user = create(:user)
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
