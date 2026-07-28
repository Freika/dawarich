# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BoundaryResolverJob do
  let(:user) { create(:user) }
  let(:session_id) { SecureRandom.uuid }
  let(:session_manager) do
    instance_double(
      Tracks::SessionManager,
      session_exists?: true,
      all_chunks_completed?: true,
      mark_failed: true
    )
  end
  let(:timeout_error) do
    Tracks::PerUserLock::AcquisitionTimeout.new(
      "Tracks::PerUserLock: could not acquire lock for user_id=#{user.id} within 30.0s"
    )
  end

  before do
    allow(Tracks::SessionManager).to receive(:new).with(user.id, session_id).and_return(session_manager)
    allow(Tracks::PerUserLock).to receive(:with_user_lock).with(user.id).and_raise(timeout_error)
    allow(ExceptionReporter).to receive(:call)
  end

  it 'retries boundary resolution without failing the session or reporting expected lock contention' do
    expect { described_class.perform_now(user.id, session_id) }
      .to have_enqueued_job(described_class).with(user.id, session_id)

    expect(session_manager).not_to have_received(:mark_failed)
    expect(ExceptionReporter).not_to have_received(:call)
  end

  it 'logs, fails the session, and stops retrying once attempts are exhausted' do
    allow(Rails.logger).to receive(:error)
    job = described_class.new(user.id, session_id)
    job.exception_executions = { '[Tracks::PerUserLock::AcquisitionTimeout]' => 4 }

    expect { job.perform_now }.not_to have_enqueued_job(described_class)

    expect(Rails.logger).to have_received(:error)
      .with(/BoundaryResolverJob lock contention retries exhausted user_id=#{user.id}/)
    expect(session_manager).to have_received(:mark_failed)
  end
end
