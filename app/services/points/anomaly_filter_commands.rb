# frozen_string_literal: true

module Points::AnomalyFilterCommands
  HANDLERS = {
    'points.anomaly_recalculate' => {
      guard: 'Recalculates current detached-point geometry under the canonical tracks owner; ' \
             'a repeat costs one convergent rebuild',
      call: ->(payload) { recalculate(payload) }
    },
    'points.anomaly_stats' => {
      guard: 'CalculatingJob recomputes the current month under stat.lock!; ' \
             'a repeat costs one convergent month refresh',
      call: ->(payload) { stats(payload) }
    }
  }.freeze

  module_function

  def recalculate(payload)
    track = Track.find_by(id: payload.fetch('track_id'), user_id: payload.fetch('user_id'))
    return unless track

    ActiveRecord::Base.transaction do
      if JobOwnership.lock_owner('command:tracks.recalculate') == :oban
        JobOutbox.insert_all([{ event_id: SecureRandom.uuid, command_type: 'points.anomaly_recalculate',
                               command_version: 1, payload:, aggregate_id: track.id,
                               metadata: { 'producer' => 'Rails Points::AnomalyFilterCommands' },
                               scheduled_at: Time.current }])
      else
        job = Tracks::RecalculateJob.new(track.id)
        job.queue_name = payload['job_queue'] if payload['job_queue']
        job.enqueue
      end
    end
  end

  def stats(payload)
    return unless User.exists?(id: payload.fetch('user_id'))

    Time.use_zone(payload.fetch('time_zone')) do
      job = Stats::CalculatingJob.new(payload.fetch('user_id'), payload.fetch('year'), payload.fetch('month'))
      job.queue_name = payload['job_queue'] if payload['job_queue']
      job.enqueue
    end
  end

  def rehome_pending!(by:)
    ActiveRecord::Base.transaction do
      pending = JobOutbox.pending.where(command_type: 'points.anomaly_recalculate', command_version: 1)
      total = pending.count
      next({ moved: 0, left: total, error: 'not_owner' }) unless
        JobOwnership.lock_owner('command:tracks.recalculate') == :sidekiq

      pushed, error = push_pending(pending.lock('FOR UPDATE SKIP LOCKED').to_a)
      JobOutbox.where(event_id: pushed).delete_all
      Rails.logger.info("Anomaly recalculation handback by #{by}: moved #{pushed.size}, left #{total - pushed.size}")
      { moved: pushed.size, left: total - pushed.size, error: }.compact
    end
  end

  def push_pending(rows)
    pushed = []
    rows.each do |row|
      track = Track.find_by(id: row.payload.fetch('track_id'), user_id: row.payload.fetch('user_id'))
      if track
        job = Tracks::RecalculateJob.new(track.id)
        job.queue_name = row.payload['job_queue'] if row.payload['job_queue']
        raise 'Tracks recalculation enqueue declined' unless job.enqueue(wait_until: row.scheduled_at)
      end
      pushed << row.event_id
    end
    [pushed, nil]
  rescue StandardError => e
    [pushed, e.class.name]
  end

  private_class_method :push_pending
end
