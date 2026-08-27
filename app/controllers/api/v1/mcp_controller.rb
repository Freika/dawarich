# frozen_string_literal: true

module Api
  module V1
    class McpController < ApiController
      def handle
        status, headers, body = transport.handle_request(request)

        headers.each { |key, value| response.set_header(key, value) }
        self.status = status
        self.response_body = body
      end

      private

      def transport
        server = MCP::Server.new(
          name: 'dawarich',
          title: 'Dawarich',
          version: APP_VERSION,
          instructions: 'Use these read-only tools to inspect the authenticated users own location history.',
          tools: [Mcp::GetTimelineTool, Mcp::GetLatestLocationTool],
          server_context: { user: current_api_user },
          configuration: mcp_configuration
        )

        MCP::Server::Transports::StreamableHTTPTransport.new(
          server,
          stateless: true,
          enable_json_response: true,
          allowed_hosts: allowed_hosts
        )
      end

      def allowed_hosts
        ENV.fetch('APPLICATION_HOSTS', 'localhost').split(',').map(&:strip).reject(&:blank?)
      end

      def mcp_configuration
        MCP::Configuration.new(validate_tool_call_results: true).tap do |configuration|
          configuration.exception_reporter = lambda do |exception, _context|
            ExceptionReporter.call(exception, 'MCP request failed')
          end
        end
      end
    end
  end
end
