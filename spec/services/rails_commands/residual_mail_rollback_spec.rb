# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Residual mail rollback' do
  it 'residual commands rehome pending events to existing Rails mail callers' do
    buffer = StringIO.new
    logger = ActiveSupport::Logger.new(buffer)
    allow(Rails).to receive(:logger).and_return(logger)
    allow(ActiveJob::Base).to receive(:logger).and_return(logger)
    allow(ActionMailer::Base).to receive(:logger).and_return(logger)
    markers = ['a12c-body-marker', 'a12c-raw-token', 'https://synthetic.test/?token=a12c-raw-token']

    %i[monthly yearly].product(['', 'invalid', 'de']).each do |period, preference|
      user = create(:user, settings: { 'locale' => preference })
      type = "mail.digest.#{period}"
      job_owner!("command:#{type}", :oban)
      payload = { 'user_id' => user.id, 'year' => 2024, 'time_zone' => 'Europe/Berlin', 'locale' => 'fr' }
      payload['month'] = 2 if period == :monthly
      JobCommands.produce(type, payload, aggregate_id: user.id, producer: 'A12c test')
      event = JobOutbox.where(command_type: type).sole.event_id
      clear_enqueued_jobs
      expect(JobCommands.rehome!(type, by: 'A12c test')).to eq(moved: 1, left: 0)
      expect(JobOutbox.exists?(event_id: event)).to be(false)
      expect(JobOwnership.lock_owner("command:#{type}")).to eq(:sidekiq)
      job = enqueued_jobs.sole
      klass = period == :monthly ? Users::Digests::Monthly::EmailSendingJob : Users::Digests::Yearly::EmailSendingJob
      expect(job[:job]).to eq(klass)
      args = [user.id, 2024]
      args << 2 if period == :monthly
      expect(ActiveJob::Arguments.deserialize(job[:args])).to eq(args)
      expect(job['locale']).to eq('fr')
      expect(job['timezone']).to eq('Europe/Berlin')

      job_owner!("command:#{type}", :oban)
      JobCommands.produce(type, payload, aggregate_id: user.id, producer: 'A12c failure')
      clear_enqueued_jobs
      allow(klass.queue_adapter).to receive(:enqueue).and_raise(IOError, markers.join(' '))
      allow(klass.queue_adapter).to receive(:enqueue_at).and_raise(IOError, markers.join(' '))
      expect(JobCommands.rehome!(type, by: 'A12c test')).to eq(moved: 0, left: 1, error: 'IOError')
      expect(JobOutbox.where(command_type: type).count).to eq(1)
      JobOutbox.where(command_type: type).delete_all
      allow(klass.queue_adapter).to receive(:enqueue).and_call_original
      allow(klass.queue_adapter).to receive(:enqueue_at).and_call_original
    end

    family = create(:family)
    target = create(:user, settings: { 'locale' => 'de' })
    requester = family.creator
    requester.update!(settings: requester.settings.merge('timezone' => 'Europe/Berlin'))
    request = create(:family_location_request, requester:, target_user: target, family:)
    key = "family_location_request_mail:#{request.id}"
    Rails.cache.delete(key)
    payload = { 'user_id' => requester.id, 'request_id' => request.id }
    job_owner!('command:mail.family_location_request', :oban)
    JobCommands.produce('mail.family_location_request', payload, aggregate_id: requester.id, producer: 'A12c test')
    clear_enqueued_jobs
    expect(JobCommands.rehome!('mail.family_location_request', by: 'A12c test')).to eq(moved: 1, left: 0)
    expect(enqueued_jobs.sole[:job]).to eq(ActionMailer::MailDeliveryJob)
    expect(enqueued_jobs.sole[:args].first(2)).to eq(%w[FamilyMailer location_request])
    expect(enqueued_jobs.sole['timezone']).to eq('Europe/Berlin')
    expect(Rails.cache.exist?(key)).to be(true)
    markers.each { |marker| expect(buffer.string.include?(marker)).to be(false), 'sensitive mail marker logged' }
  ensure
    Rails.cache.delete(key) if key
  end
end
