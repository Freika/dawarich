# frozen_string_literal: true

module UserHelper
  QR_CACHE = ActiveSupport::Cache::MemoryStore.new(size: 2.megabytes)

  def api_key_qr_code(user, size: ResponsiveQrSvg::DEFAULT_MODULE_SIZE)
    payload = { 'server_url' => root_url, 'api_key' => user.api_key }.to_json
    key = "#{Digest::SHA256.hexdigest(payload)}:#{size}"
    QR_CACHE.fetch(key) { ResponsiveQrSvg.call(payload, size: size) }.html_safe
  end
end
