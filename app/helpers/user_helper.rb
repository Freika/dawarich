# frozen_string_literal: true

module UserHelper
  def api_key_qr_code(user, size: 6)
    json = { 'server_url' => root_url, 'api_key' => user.api_key }
    qrcode = RQRCode::QRCode.new(json.to_json)
    svg = qrcode.as_svg(
      color: '000',
      fill: 'fff',
      shape_rendering: 'crispEdges',
      module_size: size,
      standalone: true,
      use_path: true,
      offset: 5
    )
    svg.html_safe
  end
end
