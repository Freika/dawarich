# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require_relative '../../app-phoenix/scripts/rate_limit_bench'

RSpec.describe RateLimitBench do
  it 'runs points and tiles at the pool concurrency and samples while clients are active' do
    ready = Queue.new
    proceed = Queue.new
    sampled = Queue.new
    lock = Mutex.new
    active = 0
    maximum = 0
    client = lambda do |phase, index|
      lock.synchronize do
        active += 1
        maximum = [maximum, active].max
      end
      if index < 4
        ready << phase
        proceed.pop
      end
      lock.synchronize { active -= 1 }
      0.001 * (index + 1)
    end
    sampler = lambda do
      sampled << true if lock.synchronize { active == 4 }
      { 'cl_waiting' => 0, 'maxwait' => 0, 'maxwait_us' => 10 }
    end
    bench = described_class.new(4, client: client, sampler: sampler)
    worker = Thread.new { bench.run({ 'points' => 8, 'tiles' => 4 }) }
    Timeout.timeout(5) do
      2.times do |phase|
        expect(Array.new(4) { ready.pop }).to eq([phase.zero? ? 'points' : 'tiles'] * 4)
        sampled.pop
        4.times { proceed << true }
      end
      report = worker.value
      expect(report.fetch('concurrency')).to eq(4)
      expect(maximum).to eq(4)
      expect(report.fetch('phases').keys).to eq(%w[points tiles])
      expect(report.fetch('phases').fetch('points').values_at('requests', 'p50', 'p95')).to eq([8, 0.004, 0.008])
      expect(report.fetch('phases').fetch('tiles').fetch('samples')).to be >= 2
      expect(described_class::PHASES).to eq('points' => 900, 'tiles' => 500)
    end
  ensure
    worker&.kill
    worker&.join
  end

  it 'reads waiting and both wait fields by name and refuses absent pool samples' do
    text = "database|user|cl_waiting|maxwait|maxwait_us\nother|u|90|20|90\ndawarich_cloud|u|2|1|345\n"
    expect(described_class.pool_sample(text)).to eq('cl_waiting' => 2, 'maxwait' => 1, 'maxwait_us' => 345)
    expect { described_class.pool_sample(text.sub('dawarich_cloud', 'absent')) }.to raise_error(/pool sample/)
    expect { described_class.pool_sample(text.sub('maxwait_us', 'unexpected')) }.to raise_error(/pool columns/)
  end

  it 'rejects either phase beyond the baseline latency, waiting, or wait gate at identical concurrency' do
    phase = { 'requests' => 500, 'samples' => 2, 'p50' => 0.01, 'p95' => 0.02,
              'max_cl_waiting' => 0, 'maxwait' => 0, 'maxwait_us' => 10 }
    baseline = { 'concurrency' => 4, 'phases' => { 'points' => phase.dup, 'tiles' => phase.dup } }
    expect(described_class.gate!(baseline, baseline)).to be(true)
    %w[points tiles].each do |name|
      { 'p95' => 0.026, 'max_cl_waiting' => 1, 'maxwait_us' => 5_011 }.each do |field, value|
        branch = Marshal.load(Marshal.dump(baseline))
        branch['phases'][name][field] = value
        expect { described_class.gate!(branch, baseline) }.to raise_error(/#{name}/)
      end
    end
    branch = Marshal.load(Marshal.dump(baseline))
    branch['concurrency'] = 1
    expect { described_class.gate!(branch, baseline) }.to raise_error(/concurrency/)
    branch = Marshal.load(Marshal.dump(baseline))
    branch['phases']['tiles']['samples'] = 0
    expect { described_class.gate!(branch, baseline) }.to raise_error(/samples/)
  end

  it 'samples PgBouncer directly when the benchmark runs inside a container' do
    allow(ENV).to receive(:[]).with('BENCH_IN_CONTAINER').and_return('1')
    expect(described_class.pool_sample_command).to eq(
      ['psql', '-h', 'a13c_bouncer', '-p', '6432', '-U', 'dawarich_cloud',
       '-A', '-c', 'SHOW POOLS', 'pgbouncer']
    )
  end

  it 'rejects unsuccessful HTTP responses instead of treating throttles as fast requests' do
    expect(Open3).to receive(:capture3).and_return(['429 0.001', '', instance_double(Process::Status, success?: true)])
    expect { described_class.http_time('http://127.0.0.1:3911/tiles') }.to raise_error(/HTTP 429/)
  end
end
