# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::ToponymsRefreshJob do
  it 'runs the refresh service on the stats queue' do
    service = instance_double(Stats::ToponymsRefresh, call: true)
    allow(Stats::ToponymsRefresh).to receive(:new).and_return(service)

    expect(described_class.queue_name).to eq('stats')
    described_class.perform_now
    expect(service).to have_received(:call).once
  end

  it 'Oban-owned: does not refresh' do
    job_owner!(described_class::OWNER_KEY, :oban)
    allow(Stats::ToponymsRefresh).to receive(:new)

    described_class.perform_now

    expect(Stats::ToponymsRefresh).not_to have_received(:new)
  end
end
