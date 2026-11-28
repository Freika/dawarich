# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::DeliverEventJob, type: :job do
  let(:user) { create(:user) }
  let(:event) do
    AnalyticsEvent.record(user:, event: :import_succeeded, dedup_key: 'import_succeeded:1',
                          properties: { result: 'complete', files: 1 })
  end
  let(:track_url) { "#{Rybbit::HOST}/api/track" }

  it 'sends the event to the Rybbit track API and marks it delivered' do
    request = stub_request(:post, track_url).with do |req|
      body = JSON.parse(req.body)
      body['site_id'] == Rybbit::SITE_ID && body['type'] == 'custom_event' &&
        body['event_name'] == 'import_succeeded' &&
        JSON.parse(body['properties']) == { 'result' => 'complete', 'files' => 1 }
    end.to_return(status: 200, body: '{"success":true}')

    described_class.perform_now(event.id)

    expect(request).to have_been_requested.once
    expect(event.reload.delivered_at).to be_present
  end

  it 'logs a warning when Rybbit accepts the request but does not store the event' do
    stub_request(:post, track_url).to_return(status: 200, body: '{"success":true,"message":"Event not tracked - bot"}')
    allow(Rails.logger).to receive(:warn)

    described_class.perform_now(event.id)

    expect(Rails.logger).to have_received(:warn).with(/import_succeeded not tracked/)
  end

  it 'does not send an event twice' do
    event.update!(delivered_at: 1.minute.ago)

    described_class.perform_now(event.id)

    expect(a_request(:post, track_url)).not_to have_been_made
  end

  it 'leaves the event undelivered when Rybbit rejects it, so a retry can send it' do
    stub_request(:post, track_url).to_return(status: 503)

    expect { described_class.new(event.id).perform_now }.to raise_error(Rybbit::DeliveryError)
    expect(event.reload.delivered_at).to be_nil
  end
end
