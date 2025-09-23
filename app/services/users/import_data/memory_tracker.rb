# frozen_string_literal: true

class Users::ImportData::MemoryTracker
  def initialize
    @process_id = Process.pid
    @start_time = Time.current
  end

  def log(stage)
    memory_mb = current_memory_usage
    elapsed = elapsed_time

    Rails.logger.info "Memory usage at #{stage}: #{memory_mb} MB (elapsed: #{elapsed}s)"

    # Log a warning if memory usage is high
    if memory_mb > 1000 # 1GB
      Rails.logger.warn "High memory usage detected: #{memory_mb} MB at stage #{stage}"
    end

    { memory_mb: memory_mb, elapsed: elapsed, stage: stage }
  end

  private

  def current_memory_usage
    # Get memory usage from /proc/PID/status on Linux or fallback to ps
    if File.exist?("/proc/#{@process_id}/status")
      status = File.read("/proc/#{@process_id}/status")
      match = status.match(/VmRSS:\s+(\d+)\s+kB/)
      return match[1].to_i / 1024.0 if match # Convert KB to MB
    end

    # Fallback to ps command (works on macOS and Linux)
    memory_kb = `ps -o rss= -p #{@process_id}`.strip.to_i
    memory_kb / 1024.0 # Convert KB to MB
  rescue StandardError => e
    Rails.logger.warn "Failed to get memory usage: #{e.message}"
    0.0
  end

  def elapsed_time
    (Time.current - @start_time).round(2)
  end
end