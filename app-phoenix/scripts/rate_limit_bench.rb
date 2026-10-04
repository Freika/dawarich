# frozen_string_literal: true

require 'json'
require 'open3'

class RateLimitBench
  PHASES = { 'points' => 900, 'tiles' => 500 }.freeze
  LATENCY_EPSILON = 0.005
  WAIT_EPSILON = 0.005

  def initialize(concurrency, client:, sampler:)
    raise 'pool concurrency must be positive' unless concurrency.positive?

    @concurrency = concurrency
    @client = client
    @sampler = sampler
  end

  def run(phases = PHASES)
    results = phases.each_with_object({}) { |(name, count), report| report[name] = run_phase(name, count) }
    { 'concurrency' => @concurrency, 'phases' => results }
  end

  def run_phase(name, count)
    requests = Queue.new
    count.times { |index| requests << index }
    times = Queue.new
    samples = [@sampler.call]
    lock = Mutex.new
    changed = ConditionVariable.new
    stopped = false
    monitor = Thread.new do
      loop do
        done = lock.synchronize do
          changed.wait(lock, 1) unless stopped
          stopped
        end
        break if done

        samples << @sampler.call
      end
    end
    workers = Array.new(@concurrency) do
      Thread.new do
        loop do
          index = begin
            requests.pop(true)
          rescue ThreadError
            break
          end
          times << @client.call(name, index)
        end
      end
    end
    workers.each(&:value)
    samples << @sampler.call
    summarize(Array.new(count) { times.pop(true) }, samples)
  ensure
    lock&.synchronize do
      stopped = true
      changed.broadcast
    end
    monitor&.value
    workers&.each { |worker| worker.kill if worker.alive? }
  end

  def summarize(times, samples)
    times.sort!
    longest = samples.max_by { |sample| self.class.wait_seconds(sample) }
    { 'requests' => times.length, 'samples' => samples.length,
      'p50' => times[(times.length * 0.50).ceil - 1], 'p95' => times[(times.length * 0.95).ceil - 1],
      'max_cl_waiting' => samples.map { |sample| sample.fetch('cl_waiting') }.max,
      'maxwait' => longest.fetch('maxwait'), 'maxwait_us' => longest.fetch('maxwait_us') }
  end

  def self.wait_seconds(sample)
    sample.fetch('maxwait') + sample.fetch('maxwait_us') / 1_000_000.0
  end

  def self.pool_sample(text)
    lines = text.lines.map { |line| line.strip.split('|') }
    columns = lines.shift || []
    required = %w[database cl_waiting maxwait maxwait_us]
    raise 'SHOW POOLS lacks required pool columns' unless (required - columns).empty?

    rows = lines.select { |line| line[columns.index('database')] == 'dawarich_cloud' }
    raise 'SHOW POOLS has no application pool sample' if rows.empty?

    samples = rows.map do |row|
      required.drop(1).each_with_object({}) do |field, sample|
        sample[field] = Integer(row.fetch(columns.index(field)))
      end
    end
    longest = samples.max_by { |sample| wait_seconds(sample) }
    longest.merge('cl_waiting' => samples.sum { |sample| sample.fetch('cl_waiting') })
  end

  def self.gate!(branch, baseline)
    raise 'baseline concurrency differs from branch' unless branch.fetch('concurrency') == baseline.fetch('concurrency')
    raise 'benchmark requires points and tiles phases' unless branch.fetch('phases').keys.sort == %w[points tiles]

    branch.fetch('phases').each do |name, phase|
      base = baseline.fetch('phases').fetch(name)
      raise "#{name}: baseline request count differs" unless phase.fetch('requests') == base.fetch('requests')
      raise "#{name}: no pool samples" unless phase.fetch('samples').positive? && base.fetch('samples').positive?
      raise "#{name}: cl_waiting is nonzero" unless phase.fetch('max_cl_waiting').zero?
      raise "#{name}: p95 exceeds baseline + 5 ms" if phase.fetch('p95') > base.fetch('p95') + LATENCY_EPSILON
      raise "#{name}: maxwait exceeds baseline + 5 ms" if wait_seconds(phase) > wait_seconds(base) + WAIT_EPSILON
    end
    true
  end

  def self.http_time(url)
    format = %w[http_code time_total].map { |field| "%{#{field}}" }.join(' ')
    output, error, status = Open3.capture3('curl', '-sS', '-m', '10', '-o', '/dev/null', '-w', format, url)
    raise "benchmark curl failed: #{error.strip}" unless status.success?

    code, elapsed = output.split
    raise "benchmark returned HTTP #{code}" unless code == '200'

    Float(elapsed)
  end

  def self.main
    role = ENV.fetch('BENCH_ROLE')
    raise 'BENCH_ROLE must be base or branch' unless %w[base branch].include?(role)

    report_path = ENV.fetch('BENCH_REPORT')
    baseline = JSON.parse(File.read(ENV.fetch('BENCH_BASELINE'))) if role == 'branch'
    concurrency = Integer(ENV.fetch('BENCH_POOL_SIZE'))
    key = 'a13cbenchqqqqqqqqqqqqqqq'
    paths = { 'points' => '/api/v1/points', 'tiles' => '/api/v1/tiles/points/0/0/0.mvt' }
    client = lambda do |phase, _index|
      http_time("http://127.0.0.1:3911#{paths.fetch(phase)}?api_key=#{key}&start_at=2026-01-01&end_at=2026-01-02")
    end
    sampler = lambda do
      output, error, status = Open3.capture3('docker', 'exec', '-e', 'PGPASSWORD=cloud', 'a13c_db',
                                             'psql', '-h', 'a13c_bouncer', '-p', '6432', '-U', 'dawarich_cloud',
                                             '-A', '-c', 'SHOW POOLS', 'pgbouncer')
      raise "SHOW POOLS failed: #{error.strip}" unless status.success?

      pool_sample(output)
    end
    report = new(concurrency, client: client, sampler: sampler).run
    File.write(report_path, "#{JSON.pretty_generate(report)}\n")
    puts JSON.generate(report)
    gate!(report, baseline) if baseline
    puts "rate limit bench: #{role == 'base' ? 'baseline recorded' : 'gate passed'}"
  end
end

RateLimitBench.main if $PROGRAM_NAME == __FILE__
