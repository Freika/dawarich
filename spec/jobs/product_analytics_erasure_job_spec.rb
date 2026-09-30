# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProductAnalyticsErasureJob, type: :job do
  it 'requests person and event deletion for the revoked pseudonymous ID' do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PERSONAL_API_KEY').and_return('test-personal-key')
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PROJECT_ID').and_return('123')
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('PRODUCT_POSTHOG_PERSONAL_API_KEY').and_return('test-personal-key')
    allow(ENV).to receive(:fetch).with('PRODUCT_POSTHOG_PROJECT_ID').and_return('123')
    id = SecureRandom.uuid
    request = stub_request(:post, 'https://eu.posthog.com/api/projects/123/persons/bulk_delete/')
              .with do |r|
      JSON.parse(r.body) == { 'distinct_ids' => [id], 'delete_events' => true,
                              'delete_recordings' => true }
    end
              .to_return(status: 202)

    described_class.perform_now(id)

    expect(request).to have_been_requested.once
  end
end
