# frozen_string_literal: true

module UserHelper
  def api_key_qr_code(user, size: ResponsiveQrSvg::DEFAULT_MODULE_SIZE)
    payload = { 'server_url' => root_url, 'api_key' => user.api_key }.to_json
    ResponsiveQrSvg.call(payload, size: size).html_safe
  end

  def settings_time_zone_options
    ActiveSupport::TimeZone.all
                           .map { |tz| [tz.tzinfo.name, tz.formatted_offset, tz.utc_offset] }
                           .uniq(&:first)
                           .sort_by { |_, _, seconds| seconds }
                           .map { |iana, offset, _| ["(GMT#{offset}) #{iana}", iana] }
  end
end
