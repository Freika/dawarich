# frozen_string_literal: true

module PhoenixEventsPoller
  POLL_SECONDS = 1
  BACKOFF_SECONDS = 5
  THREAD_LOCK = Mutex.new

  def start
    return if Rails.env.test?

    THREAD_LOCK.synchronize { poller_thread || spawn_poller }
  end

  def stop
    thread = poller_thread
    thread&.kill
    thread&.join
  end

  def drain_safely
    sleep(POLL_SECONDS) if Rails.application.executor.wrap { drain_once }.zero?
  rescue StandardError => e
    Rails.logger.warn("#{self::LOG_TAG}: #{e.class}")
    sleep(BACKOFF_SECONDS)
  end

  private

  def poller_thread
    Thread.list.find { |thread| thread.name == self::THREAD_NAME }
  end

  def spawn_poller
    thread = Thread.new { loop { drain_safely } }
    thread.name = self::THREAD_NAME
    thread
  end
end
