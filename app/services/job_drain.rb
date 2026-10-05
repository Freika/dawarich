# frozen_string_literal: true

require 'sidekiq/api'

module JobDrain
  WRAPPERS = %w[Sidekiq::ActiveJob::Wrapper ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper].freeze

  module_function

  def status
    counts = { queued: 0, scheduled: 0, retry: 0, dead: 0, busy: 0, unknown: 0 }
    classes = Hash.new(0)
    reasons = []
    queues = Sidekiq::Queue.all
    queues.each { |queue| count_set(queue, :queued, counts, classes, reasons) }
    { scheduled: Sidekiq::ScheduledSet.new, retry: Sidekiq::RetrySet.new, dead: Sidekiq::DeadSet.new }
      .each { |key, set| count_set(set, key, counts, classes, reasons) }
    Sidekiq::WorkSet.new.each do |_, _, work|
      counts[:busy] += 1
      count_job(work.job.item, counts, classes)
    end
    processes = Sidekiq::ProcessSet.new(false).to_a
    busy = processes.sum { |process| process['busy'].to_i }
    reasons << 'busy_unreadable' if busy != counts[:busy]
    counts[:busy] = [counts[:busy], busy].max
    reasons << 'process_heartbeat_invalid' if processes.any? { |process| process['beat'].to_f < 60.seconds.ago.to_f }
    reasons << 'unknown_work' if counts[:unknown].positive?
    counts.each { |key, count| reasons << "#{key}_work" if key != :unknown && count.positive? }
    gauges = JobHealth.gauges
    reasons << 'database_unreadable' unless gauges[:tables] == true
    {
      status: reasons.empty? ? 'OBSERVED_EMPTY' : 'BLOCKED', observation: true,
      counts:, classes: classes.sort.to_h, reasons: reasons.uniq.sort
    }
  rescue StandardError
    { status: 'BLOCKED', observation: true, reasons: ['redis_unreadable'] }
  end

  def count_set(set, key, counts, classes, reasons)
    before = set.size
    seen = 0
    set.each do |job|
      seen += 1
      count_job(job.item, counts, classes)
    end
    after = set.size
    reasons << 'changed_during_read' unless before == seen && seen == after
    counts[key] += [before, seen, after].max
  end

  def count_job(item, counts, classes)
    name = item['wrapped']
    klass = if name.is_a?(String) && name.size <= 128 && name.match?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/)
              name.safe_constantize
            end
    if WRAPPERS.include?(item['class']) && klass.is_a?(Class) && klass < ActiveJob::Base
      classes[name] += 1
    else
      counts[:unknown] += 1
      classes['unknown'] += 1
    end
  end
end
