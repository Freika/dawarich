# frozen_string_literal: true

# This file is used by Rack-based servers to start the application.

require_relative 'config/environment'

if (relative_url_root = Rails.application.config.relative_url_root.presence)
  map(relative_url_root) { run Rails.application }
else
  run Rails.application
end
Rails.application.load_server
