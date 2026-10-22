# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Account deletion confirmation retry after a failed request' do
  let(:user) { create(:user) }

  def request_confirmation
    Users::RequestAccountDestroy.new(user, host: 'example.com', protocol: 'https').call
  end

  it 'releases the rate limit after token generation fails' do
    allow(JWT).to receive(:encode).and_raise(StandardError, 'Token generation unavailable')

    expect { request_confirmation }.to raise_error(StandardError, 'Token generation unavailable')
    allow(JWT).to receive(:encode).and_call_original

    expect(request_confirmation.status).to eq(:sent)
    expect(enqueued_jobs.count { |job| job[:job] == Users::MailerSendingJob }).to eq(1)
  end

  it 'releases the rate limit when the job adapter rejects enqueueing' do
    adapter = ActiveJob::Base.queue_adapter
    allow(adapter).to receive(:enqueue).and_raise(ActiveJob::EnqueueError, 'Queue unavailable')

    expect { request_confirmation }.to raise_error(ActiveJob::EnqueueError)
    allow(adapter).to receive(:enqueue).and_call_original

    expect(request_confirmation.status).to eq(:sent)
    expect(enqueued_jobs.count { |job| job[:job] == Users::MailerSendingJob }).to eq(1)
  end

  it 'keeps a successfully acquired rate limit while later requests are throttled' do
    expect(request_confirmation.status).to eq(:sent)
    allow(JWT).to receive(:encode).and_raise(StandardError, 'Token generation unavailable')

    expect(request_confirmation.status).to eq(:throttled)
    expect(request_confirmation.status).to eq(:throttled)
    expect(JWT).not_to have_received(:encode)
    expect(enqueued_jobs.count { |job| job[:job] == Users::MailerSendingJob }).to eq(1)
  end
end
