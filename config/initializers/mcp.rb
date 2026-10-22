# frozen_string_literal: true

MCP.configure do |config|
  config.validate_tool_call_results = true
  config.exception_reporter = lambda do |exception, _context|
    Rails.logger.error("MCP request failed: #{exception.full_message(highlight: false)}")
    ExceptionReporter.call(exception, 'MCP request failed')
  end
end
