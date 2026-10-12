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

  it 'does not report a session that expires during boundary resolution' do
    boundary_detector = instance_double(Tracks::BoundaryDetector, resolve_cross_chunk_tracks: 1)
    allow(Tracks::PerUserLock).to receive(:with_user_lock).with(user.id).and_yield
    allow(Tracks::BoundaryDetector).to receive(:new).with(user).and_return(boundary_detector)
    allow(session_manager).to receive_messages(get_session_data: nil, mark_completed: false)

    described_class.perform_now(user.id, session_id)

    expect(boundary_detector).to have_received(:resolve_cross_chunk_tracks)
    expect(session_manager).to have_received(:mark_completed)
    expect(ExceptionReporter).not_to have_received(:call)
    expect(session_manager).not_to have_received(:mark_failed)
  end

  describe 'rescheduling while chunks are still running' do
    let(:pending_session) do
      instance_double(
        Tracks::SessionManager,
        session_exists?: true,
        all_chunks_completed?: false,
        session_id: session_id,
        mark_failed: true
      )
    end

    before do
      allow(Tracks::SessionManager).to receive(:new).with(user.id, session_id).and_return(pending_session)
    end

    def reschedules
      ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == described_class }
    end

    it 'keeps the reschedule on the queue it was running on, not the class default' do
      allow(pending_session).to receive(:get_session_data).and_return({ 'completed_chunks' => 1 })

      described_class.set(queue: :low_priority).perform_now(user.id, session_id)

      expect(reschedules.map { |job| job[:queue] }).to eq(['low_priority'])
    end

    it 'does not spend an attempt while chunks are still completing' do
      allow(pending_session).to receive(:get_session_data).and_return({ 'completed_chunks' => 7 })

      described_class.perform_now(user.id, session_id, 3, 4)

      expect(reschedules.first[:args][2]).to eq(0)
      expect(pending_session).not_to have_received(:mark_failed)
    end

    it 'keeps backing off as it polls, so progress does not restart a 30s loop' do
      allow(pending_session).to receive(:get_session_data).and_return({ 'completed_chunks' => 9 })

      described_class.perform_now(user.id, session_id, 0, 4, 4)

      delay = reschedules.first[:at] - Time.current.to_f
      expect(delay).to be > 60
      expect(reschedules.first[:args][4]).to eq(5)
    end

    it 'spends an attempt when no chunk finished since the last look' do
      allow(pending_session).to receive(:get_session_data).and_return({ 'completed_chunks' => 4 })

      described_class.perform_now(user.id, session_id, 3, 4)

      expect(reschedules.first[:args][2]).to eq(4)
    end

    it 'gives up once a stalled session exhausts the attempts' do
      allow(pending_session).to receive(:get_session_data).and_return({ 'completed_chunks' => 4 })

      described_class.perform_now(user.id, session_id, described_class::MAX_RETRIES - 1, 4)

      expect(reschedules).to be_empty
      expect(pending_session).to have_received(:mark_failed).with(/Max retries/)
    end
  end
end
