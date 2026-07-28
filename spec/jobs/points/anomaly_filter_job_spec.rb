# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyFilterJob do
  include ActiveJob::TestHelper

  it 'retries transient database deadlocks' do
    filter = instance_double(Points::AnomalyFilter)
    allow(Points::AnomalyFilter).to receive(:new).with(42, 100, 200).and_return(filter)
    allow(filter).to receive(:call).and_raise(ActiveRecord::Deadlocked, 'deadlock detected')

    expect do
      described_class.perform_now(42, 100, 200)
    end.to have_enqueued_job(described_class).with(42, 100, 200)
  end

  it 'logs the error with job context when retries are exhausted' do
    filter = instance_double(Points::AnomalyFilter)
    allow(Points::AnomalyFilter).to receive(:new).with(42, 100, 200).and_return(filter)
    allow(filter).to receive(:call).and_raise(ActiveRecord::Deadlocked, 'deadlock detected')
    allow(Rails.logger).to receive(:error)

    job = described_class.new(42, 100, 200)
    job.exception_executions = { '[ActiveRecord::Deadlocked]' => 2 }

    expect { job.perform_now }.not_to have_enqueued_job(described_class)

    expect(Rails.logger).to have_received(:error).with(
      /Points::AnomalyFilterJob retries exhausted user_id=42 range=100\.\.200: ActiveRecord::Deadlocked/
    )
  end
end
