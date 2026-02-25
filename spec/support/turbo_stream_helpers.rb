# frozen_string_literal: true

module TurboStreamHelpers
  def expect_turbo_stream_response
    expect(response.media_type).to eq('text/vnd.turbo-stream.html')
  end

  def expect_turbo_stream_action(action, target)
    expect(response.body).to include("<turbo-stream action=\"#{action}\" target=\"#{target}\">")
  end

  def expect_flash_stream(message = nil)
    expect_turbo_stream_action('append', 'flash-messages')
    expect(response.body).to include(message) if message
  end
end

RSpec.configure do |config|
  config.include TurboStreamHelpers, type: :request
end
