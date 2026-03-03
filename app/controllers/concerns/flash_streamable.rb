# frozen_string_literal: true

module FlashStreamable
  extend ActiveSupport::Concern

  private

  def stream_flash(type, message)
    turbo_stream.append('flash-messages', partial: 'shared/flash_message', locals: { type: type, message: message })
  end
end
