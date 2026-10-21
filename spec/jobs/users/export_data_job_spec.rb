# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportDataJob, type: :job do
  let(:user) { create(:user) }
  let(:export_data) { Users::ExportData.new(user) }

  it 'exports the user data' do
    expect(Users::ExportData).to receive(:new).with(user).and_return(export_data)
    expect(export_data).to receive(:export)

    Users::ExportDataJob.perform_now(user.id)
  end
  it 'unchanged User export producer routes through the job shim' do
    user
    job_owner!('command:users.export_data', :sidekiq)
    job, serialized = Time.use_zone('America/New_York') do
      I18n.with_locale(:fr) do
        job = user.export_data
        [job, job.serialize]
      end
    end
    expect(job).to be_a(Users::ExportDataJob)
    expect(job.queue_name).to eq('exports')
    expect(Users::ExportData).to receive(:new).with(user).once.and_return(export_data)
    expect(export_data).to receive(:export).once
    ActiveJob::Base.execute(serialized)
    expect(JobOutbox.count).to eq(0)
    clear_enqueued_jobs
    job_owner!('command:users.export_data', :oban)
    forwarded, payload = Time.use_zone('America/New_York') do
      I18n.with_locale(:fr) do
        job = user.export_data
        [job, job.serialize]
      end
    end
    user.update!(settings: user.settings.merge('timezone' => 'Europe/Berlin'))
    expect(Users::ExportData).not_to receive(:new)
    expect { 2.times { ActiveJob::Base.execute(payload) } }.not_to change(Export, :count)
    row = JobOutbox.find(forwarded.job_id)
    expect(row.command_type).to eq('users.export_data')
    expect(row.command_version).to eq(1)
    expect(row.payload).to eq({ 'user_id' => user.id, 'time_zone' => 'America/New_York', 'locale' => 'fr' })
    expect(JobOutbox.count).to eq(1)
    expect(Users::ExportDataJob.enqueue_after_transaction_commit).to be(false)
  end

  it 'legacy backup failure keeps Rails failed row' do
    job_owner!('command:users.export_data', :sidekiq)
    allow_any_instance_of(Users::ExportData).to receive(:create_zip_archive).and_raise(StandardError,
                                                                                       'synthetic ZIP failure')
    allow(ExceptionReporter).to receive(:call)
    expect { described_class.perform_now(user.id) }.to raise_error(StandardError, 'synthetic ZIP failure')
    expect(user.exports.pluck(:status, :error_message)).to eq([['failed', nil]])
    expect(user.notifications.count).to eq(0)
  end
end
