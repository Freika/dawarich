# frozen_string_literal: true

class BackfillInstanceGeocodingSettings < ActiveRecord::Migration[8.0]
  def up
    Geocoding::BackfillInstanceSettings.call
  end

  # Removes only what the backfill could have written, and only while it is
  # still untouched — an operator who has since edited a value in the admin page
  # should keep it.
  def down
    InstanceSetting.where(key: %w[photon_api_host photon_api_key photon_api_use_https
                                  nominatim_api_host nominatim_api_key nominatim_api_use_https
                                  geoapify_api_key locationiq_api_key reverse_geocoding_rps])
                   .where('created_at = updated_at')
                   .delete_all
  end
end
