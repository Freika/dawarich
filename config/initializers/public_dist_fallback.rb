# frozen_string_literal: true

if Rails.application.config.public_file_server.enabled
  Rails.application.config.middleware.insert_after(
    ActionDispatch::Static,
    ActionDispatch::Static,
    Rails.root.join('public_dist').to_s,
    headers: Rails.application.config.public_file_server.headers || {}
  )
end
