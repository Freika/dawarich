# frozen_string_literal: true

class SeedGeocodingServiceSettingsFromEnv < ActiveRecord::Migration[8.0]
  def up
    return unless DawarichSettings.self_hosted?
    return unless DawarichSettings.reverse_geocoding_enabled?

    User.find_each { |user| Geocoding::SeedFromEnv.call(user) }
  end

  def down; end
end
