# frozen_string_literal: true

require 'sidekiq/api'
require 'sidekiq/limit_fetch'
require 'digest'

module JobDrain
  WRAPPERS = %w[Sidekiq::ActiveJob::Wrapper ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper].freeze

  module_function

  def status(phase: :post_stop)
    raise ArgumentError unless %i[pre_quiet quiet post_stop].include?(phase)

    before = fingerprint
    counts = { queued: 0, scheduled: 0, retry: 0, dead: 0, busy: 0, unknown: 0 }
    classes = Hash.new(0)
    reasons = []
    queues = observed_queues
    queues.each { |queue| count_set(queue, :queued, counts, classes, reasons) }
    { scheduled: Sidekiq::ScheduledSet.new, retry: Sidekiq::RetrySet.new, dead: Sidekiq::DeadSet.new }
      .each { |key, set| count_set(set, key, counts, classes, reasons) }
    Sidekiq::WorkSet.new.each do |_, _, work|
      counts[:busy] += 1
      count_job(work.job.item, counts, classes)
    end
    processes = Sidekiq::ProcessSet.new(false).to_a
    Sidekiq.redis do |redis|
      reasons << 'process_registration_unreadable' if redis.scard('processes') != processes.size
      orphaned = scan_keys(redis, '*:work') - processes.map { "#{_1.identity}:work" }
      reasons << 'busy_unreadable' if orphaned.any? { redis.hlen(_1).positive? }
    end
    busy = processes.sum { |process| process['busy'].to_i }
    reasons << 'busy_unreadable' if busy != counts[:busy]
    counts[:busy] = [counts[:busy], busy].max
    reasons << 'process_heartbeat_invalid' if processes.any? { |process| process['beat'].to_f < 60.seconds.ago.to_f }
    fetch = fetch_status(queues, processes, counts, reasons, phase)
    reasons << 'unknown_work' if counts[:unknown].positive?
    counts.each { |key, count| reasons << "#{key}_work" if key != :unknown && count.positive? }
    gauges = JobHealth.gauges(include_drain: true)
    bridge = bridge_status(gauges[:drain])
    reasons << 'database_unreadable' unless gauges[:tables] == true && bridge[:counts]
    reasons << 'changed_during_read' unless before == fingerprint
    reasons << 'sql_bridge_blocked' if bridge[:shutdown] == 'BLOCKED'
    unknown = bridge[:certainty] == 'UNKNOWN' ||
              reasons.any? { _1.match?(/unreadable|invalid|inconsistent|changed_during_read/) }
    {
      status: reasons.empty? ? 'OBSERVED_EMPTY' : 'BLOCKED', observation: true,
      certainty: unknown ? 'UNKNOWN' : 'OBSERVED',
      phase:, fetch:,
      counts:, classes: classes.sort.to_h, reasons: reasons.uniq.sort, bridge:
    }
  rescue StandardError
    { status: 'BLOCKED', certainty: 'UNKNOWN', observation: true, reasons: ['redis_unreadable'] }
  end

  def observed_queues
    configured = YAML.safe_load(ERB.new(Rails.root.join('config/sidekiq.yml').read).result,
                                permitted_classes: [Symbol]).fetch(:queues)
    names = Sidekiq::Queue.all.map(&:name) + configured + Array(Sidekiq.default_configuration[:queues])
    Sidekiq.redis do |redis|
      scan_keys(redis, 'queue:*').each { names << _1.delete_prefix('queue:') }
      reservation_keys(redis).each { names << _1.split(':', 3).last }
    end
    names.uniq.sort.map { Sidekiq::Queue[_1] }
  end

  def reservation_keys(redis)
    %w[busy probed].flat_map { scan_keys(redis, "#{Sidekiq::LimitFetch::Global::Semaphore::PREFIX}:#{_1}:*") }
  end

  def scan_keys(redis, pattern)
    cursor = '0'
    keys = []
    loop do
      cursor, page = redis.call('SCAN', cursor, 'MATCH', pattern, 'COUNT', 100)
      keys.concat(page)
      break if cursor == '0'
    end
    keys
  end

  def fingerprint
    Sidekiq.redis do |redis|
      processes = redis.smembers('processes')
      monitor = Sidekiq::LimitFetch::Global::Monitor
      fetchers = monitor.all_processes
      keys = %w[queues schedule retry dead processes] + [monitor::PROCESS_SET] +
             scan_keys(redis, 'queue:*') + scan_keys(redis, '*:work') + reservation_keys(redis) +
             processes.flat_map { [_1, "#{_1}:work"] } + fetchers.map { monitor::HEARTBEAT_PREFIX + _1 }
      Digest::SHA256.hexdigest(Marshal.dump(keys.uniq.sort.map { [_1, redis.call('DUMP', _1)] }))
    end
  end

  def fetch_status(queues, processes, counts, reasons, phase)
    monitor = Sidekiq::LimitFetch::Global::Monitor
    fetchers = monitor.all_processes
    reservations = queues.map do |queue|
      { busy: queue.lock.busy_processes, probed: queue.lock.probed_processes }
    end
    busy = reservations.flat_map { _1[:busy] }
    probed = reservations.flat_map { _1[:probed] }
    invalid = reservations.any? { |row| row[:busy].tally.any? { |id, count| count > row[:probed].tally.fetch(id, 0) } }
    reasons << 'fetch_state_inconsistent' if invalid || ((busy + probed).uniq - fetchers).any? ||
                                             busy.size != counts[:busy]
    reasons << 'fetch_heartbeat_invalid' if monitor.old_processes.any?
    reasons << 'fetched_work' if busy.any?
    reasons << 'fetch_probes_present' if phase != :pre_quiet && probed.any?
    reasons << 'fetchers_present' if phase == :post_stop && fetchers.any?
    reasons << 'processes_present' if phase == :post_stop && processes.any?
    reasons << 'processes_not_quiet' if phase == :quiet && processes.any? { !_1['quiet'] }
    { busy: busy.size, probed: probed.size, processes: fetchers.size }
  end

  def bridge_status(drain)
    unless drain && drain[:tables] == true && drain[:counts]['incomplete_oban']
      return { forward: 'BLOCKED', shutdown: 'BLOCKED', binary_rollback: 'BLOCKED',
               reasons: ['database_unreadable'] }
    end

    counts = drain[:counts]
    common = %w[pending_outbox quarantined reverse_pending reverse_dead release_pending].select { counts[_1].positive? }
    common << 'legacy_schedulers' if drain[:legacy_schedulers].any? { _1[:incomplete].positive? }
    forward = common + %w[missing_owners mixed_owners unknown_owners].select { counts[_1].positive? }
    if counts['stale_nodes'].positive? || (counts['oban_owners'].positive? && counts['fresh_nodes'].zero?)
      forward << 'heartbeat_invalid'
    end
    forward << 'residual_producers' if drain[:producer_kinds].any? { _1[:status] == 'BLOCKED' }
    binary = common + %w[incomplete_oban unfinished_generations missing_owners unknown_owners unpinned_rollback_owners]
             .select { counts[_1].positive? }
    binary << 'heartbeat_invalid' if forward.include?('heartbeat_invalid')
    shutdown = forward + %w[incomplete_oban unfinished_generations].select { counts[_1].positive? }
    {
      certainty: forward.include?('heartbeat_invalid') ? 'UNKNOWN' : 'OBSERVED',
      shutdown: shutdown.empty? ? 'OBSERVED_EMPTY' : 'BLOCKED', shutdown_reasons: shutdown.sort,
      forward: forward.empty? ? 'OBSERVED_EMPTY' : 'BLOCKED',
      binary_rollback: binary.empty? ? 'OBSERVED_EMPTY' : 'BLOCKED', observation: true,
      forward_reasons: forward.sort, binary_reasons: binary.sort, counts:
    }
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
