# frozen_string_literal: true

module UserHelper
  def api_key_qr_code(user)
    qrcode = RQRCode::QRCode.new(user.api_key)
    svg = qrcode.as_svg(
      color: "000",
      fill: "fff",
      shape_rendering: "crispEdges",
      module_size: 11,
      standalone: true,
      use_path: true,
      offset: 5
    )
    svg.html_safe
  end
end
