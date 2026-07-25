# frozen_string_literal: true

module Mcp
  class BaseTool < MCP::Tool
    class << self
      private

      def success(payload)
        MCP::Tool::Response.new(
          [{ type: 'text', text: JSON.generate(payload) }],
          structured_content: payload
        )
      end

      def failure(message)
        payload = { error: message }
        MCP::Tool::Response.new(
          [{ type: 'text', text: JSON.generate(payload) }],
          error: true,
          structured_content: payload
        )
      end
    end
  end
end
