# frozen_string_literal: true

require 'logger'

class SentryLogsLogger < ::Logger
  SEVERITY_MAP = {
    ::Logger::DEBUG => :debug,
    ::Logger::INFO  => :info,
    ::Logger::WARN  => :warn,
    ::Logger::ERROR => :error,
    ::Logger::FATAL => :fatal,
    ::Logger::UNKNOWN => :info
  }.freeze

  def initialize(level: ::Logger::WARN)
    super(File::NULL)
    self.level = level
  end

  def add(severity, message = nil, progname = nil, &block)
    severity ||= ::Logger::UNKNOWN
    return true if severity < level
    return true unless Sentry.initialized?

    message = block.call if message.nil? && block
    message = progname if message.nil?
    return true if message.nil?

    Thread.current[:sentry_logs_logger_in_progress] ||= false
    return true if Thread.current[:sentry_logs_logger_in_progress]

    Thread.current[:sentry_logs_logger_in_progress] = true
    begin
      Sentry.logger.public_send(SEVERITY_MAP[severity], message.to_s)
    rescue StandardError
      nil
    ensure
      Thread.current[:sentry_logs_logger_in_progress] = false
    end
    true
  end
end
