# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::FullRecalculationJob do
  let(:user) { create(:user) }

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it 'enqueues a calculation for every tracked month' do
    allow(User).to receive(:find_by).with(id: user.id).and_return(user)
    allow(user).to receive(:years_tracked).and_return([{ year: 2026, months: %w[Mar] }])

    expect { described_class.perform_now(user.id) }
      .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2026, 3)
  end

  it 'clears the debounce window so a later change schedules again' do
    debouncer = instance_double(Stats::RecalculationDebouncer, clear: true)
    allow(Stats::RecalculationDebouncer).to receive(:new).with(user.id).and_return(debouncer)

    described_class.perform_now(user.id)

    expect(debouncer).to have_received(:clear)
  end

  it 'does nothing when the user is gone' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
