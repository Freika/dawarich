# frozen_string_literal: true

module Api
  module V1
    class McpController < ApiController
      TOOLS = [McpTools::GetTimeline, McpTools::GetLatestLocation, McpTools::SearchVisits].freeze

      before_action :require_pro_api!

      def handle
        status, headers, body = transport.handle_request(request)

        headers.each { |key, value| response.set_header(key, value) }
        self.status = status
        self.response_body = body
      end

      private

      def api_key
        extract_bearer_token
      end

      def transport
        server = MCP::Server.new(
          name: 'dawarich',
          title: 'Dawarich',
          version: APP_VERSION,
          instructions: "Use these read-only tools to inspect the authenticated user's own location history.",
          tools: TOOLS,
          server_context: { user: current_api_user }
        )

        MCP::Server::Transports::StreamableHTTPTransport.new(
          server,
          stateless: true,
          enable_json_response: true,
          dns_rebinding_protection: false
        )
      end
    end
  end
end
