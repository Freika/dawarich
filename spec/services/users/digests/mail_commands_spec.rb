# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::Digests::MailCommands' do
  include ActiveSupport::Testing::TimeHelpers

  it 'digest mail shims preserve Sidekiq behavior and forward under Oban ownership' do
    buffer = StringIO.new
    logger = ActiveSupport::Logger.new(buffer)
    allow(Rails).to receive(:logger).and_return(logger)
    allow(ActiveJob::Base).to receive(:logger).and_return(logger)
    allow(ActionMailer::Base).to receive(:logger).and_return(logger)
    markers = ['a12c-body-marker', 'a12c-raw-token', 'https://synthetic.test/?token=a12c-raw-token']

    travel_to Time.utc(2026, 10, 4, 12) do
      %i[monthly yearly].product(['', 'invalid', 'de']).each do |period, preference|
        user = create(:user, settings: { 'locale' => preference, 'timezone' => 'Europe/Berlin' })
        digest = create(:users_digest, user:, period_type: period, year: 2024,
                                      month: period == :monthly ? 2 : nil, distance: 12_500)
        klass = period == :monthly ? Users::Digests::Monthly::EmailSendingJob : Users::Digests::Yearly::EmailSendingJob
        type = "mail.digest.#{period}"
        args = [user.id, 2024]
        args << 2 if period == :monthly
        job_owner!("command:#{type}", :sidekiq)
        clear_enqueued_jobs
        observed = []
        adapter = ActionMailer::MailDeliveryJob.queue_adapter
        allow(adapter).to receive(:enqueue).and_wrap_original do |original, job|
          observed << digest.reload.sent_at
          original.call(job)
        end

        I18n.with_locale(:fr) { Time.use_zone('Europe/Berlin') { klass.new.perform(*args) } }
        expect(observed).to eq([nil])
        expect(digest.reload.sent_at).to eq(Time.current)
        expect(enqueued_jobs.sole['locale']).to eq('fr')
        expect(enqueued_jobs.sole['timezone']).to eq('Europe/Berlin')
        user.update_columns(settings: user.settings.merge('locale' => 'en'))
        sent = []
        allow_any_instance_of(Mail::TestMailer).to receive(:deliver!) { |_transport, mail| sent << mail }
        ActiveJob::Base.execute(enqueued_jobs.sole)
        expect(sent.size).to eq(1)
        expected_subject = I18n.t("mailers.users.digests.#{period == :monthly ? 'monthly' : 'year_end'}.subject",
                                  locale: :en, year: 2024, month: 'February')
        expect(sent.sole.subject).to eq(expected_subject)
        clear_enqueued_jobs

        digest.update_columns(sent_at: nil)
        job_owner!("command:#{type}", :oban)
        job = klass.new(*args)
        I18n.with_locale(:fr) { Time.use_zone('Europe/Berlin') { 2.times { job.perform(*args) } } }
        expect(enqueued_jobs.size).to eq(0)
        expect(digest.reload.sent_at).to be_nil
        command = JobOutbox.find(job.job_id)
        expected = { 'user_id' => user.id, 'year' => 2024, 'time_zone' => 'Europe/Berlin', 'locale' => 'fr' }
        expected['month'] = 2 if period == :monthly
        expect(command.command_type).to eq(type)
        expect(command.command_version).to eq(1)
        expect(command.payload).to eq(expected)
        expect(JobOutbox.where(event_id: job.job_id).count).to eq(1)

        job_owner!("command:#{type}", :sidekiq)
        allow(adapter).to receive(:enqueue).and_raise(IOError, markers.join(' '))
        expect { klass.new.perform(*args) }.to raise_error(IOError)
        expect(digest.reload.sent_at).to be_nil
        expect(enqueued_jobs.size).to eq(0)
        allow(adapter).to receive(:enqueue).and_call_original
      end
    end

    markers.each { |marker| expect(buffer.string.include?(marker)).to be(false), 'sensitive mail marker logged' }
  end
end
