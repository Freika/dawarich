# frozen_string_literal: true

module McpTools
  class BaseTool < MCP::Tool
    VISIT_STATUS_NOTE = "Visit status 'confirmed' means the user confirmed the visit; " \
                        "'suggested' means Dawarich detected it automatically and it is not confirmed yet."

    class << self
      private

      def success(payload)
        MCP::Tool::Response.new(
          [{ type: 'text', text: JSON.generate(payload) }],
          structured_content: payload
        )
      end

      def failure(message)
        MCP::Tool::Response.new([{ type: 'text', text: message }], error: true)
      end
    end
  end
end
