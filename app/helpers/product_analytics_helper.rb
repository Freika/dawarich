# frozen_string_literal: true

module ProductAnalyticsHelper
  def consent_gated_tracking_attributes
    return {} if DawarichSettings.self_hosted?

    {
      'data-partnero-id': ENV['PARTNERO_PROGRAM_ID'].presence,
      'data-google-ads-id': ENV['GOOGLE_ADS_ID'].presence
    }
  end
end
