# frozen_string_literal: true

# Configure SolidCache
Rails.application.config.to_prepare do
  # Only require the entries file as it seems the Entry class is defined there
  begin
    require 'solid_cache/store/entries'
  rescue LoadError => e
    Rails.logger.warn "Could not load SolidCache: #{e.message}"
  end
end
