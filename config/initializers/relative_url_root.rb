# frozen_string_literal: true

if (relative_url_root = Rails.application.config.relative_url_root.presence)
  Rails.application.routes.default_url_options[:script_name] = relative_url_root
  ActionCable.server.config.url = "#{relative_url_root}/cable"
end
