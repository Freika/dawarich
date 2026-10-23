# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'timeout'

RSpec.describe 'Puma embedded jobs' do
  it 'executes an enqueued job and a scheduled cron job in the web process and stops gracefully' do
    Dir.mktmpdir('embedded-sidekiq') do |directory|
      marker = "embedded-probe:#{SecureRandom.hex(8)}"
      rackup = File.join(directory, 'probe.ru')
      File.write(rackup, <<~RACK)
        require_relative '#{Rails.root}/config/environment'
        class EmbeddedProbeJob
          include Sidekiq::Job
          def perform(key)
            Sidekiq.redis { |redis| redis.set(key, Process.pid) }
          end
        end
        Sidekiq::Cron.configure { |config| config.cron_poll_interval = 1 }
        Sidekiq::Cron::Job.create(name: '#{marker}', cron: '* * * * * *',
          class: 'EmbeddedProbeJob', args: ['#{marker}:cron'], queue: 'default')
        EmbeddedProbeJob.perform_async('#{marker}:queued')
        run ->(_env) { [200, { 'content-type' => 'text/plain' }, [Process.pid.to_s]] }
      RACK
      log = File.open(File.join(directory, 'puma.log'), 'w+')
      child = Process.spawn(
        { 'SIDEKIQ_EMBEDDED' => 'true', 'WEB_CONCURRENCY' => '0',
          'PIDFILE' => File.join(directory, 'puma.pid'), 'PORT' => '0' },
        'bundle', 'exec', 'puma', '-C', Rails.root.join('config/puma.rb').to_s,
        '--bind', "unix://#{directory}/puma.sock", rackup, out: log, err: log
      )
      begin
        Timeout.timeout(45) do
          loop do
            pids = Sidekiq.redis { |redis| redis.mget("#{marker}:queued", "#{marker}:cron") }
            break if pids == [child.to_s, child.to_s]

            raise 'Puma exited before processing jobs' if Process.waitpid(child, Process::WNOHANG)

            sleep 0.1
          end
        end
        socket = UNIXSocket.new(File.join(directory, 'puma.sock'))
        socket.write("GET / HTTP/1.0\r\n\r\n")
        expect(socket.read).to end_with(child.to_s)
        socket.close
        expect(Sidekiq::Cron::Job.find('stats_toponyms_refresh_job')).to be_present
        Process.kill('TERM', child)
        _, status = Timeout.timeout(30) { Process.wait2(child) }
        child = nil
        expect(status.exitstatus).to eq(0)
        log.rewind
        expect(log.read).to include('Sidekiq running embedded', 'Terminating quiet threads')
      ensure
        if child
          Process.kill('TERM', child)
          Process.wait(child)
        end
        Sidekiq::Cron::Job.find(marker)&.destroy
        Sidekiq.redis { |redis| redis.del("#{marker}:queued", "#{marker}:cron") }
        FileUtils.cp(log.path, ENV['EMBEDDED_PROBE_LOG']) if ENV['EMBEDDED_PROBE_LOG']
        log.close
      end
    end
  end
end
