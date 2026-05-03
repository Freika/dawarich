# frozen_string_literal: true

# Renders a QR code as an SVG that scales to its container.
#
# rqrcode emits an SVG with a fixed pixel width/height and no viewBox.
# That works fine when the rendered pixel size is smaller than the parent,
# but for longer payloads the QR matrix grows past common wrapper widths
# (e.g. Tailwind's `max-w-xs`) and the QR overflows or gets clipped by
# `overflow-hidden`. See GitHub issue #2479.
#
# This service runs the rqrcode SVG through a small post-processor that
# swaps the fixed pixel dimensions for `width="100%" height="100%"` and
# adds a `viewBox` derived from the original pixel size, so the SVG keeps
# its aspect ratio while filling whatever container the page provides.
class ResponsiveQrSvg
  DEFAULT_MODULE_SIZE = 6
  OFFSET = 5

  def self.call(content, size: DEFAULT_MODULE_SIZE)
    new(content, size: size).call
  end

  def initialize(content, size: DEFAULT_MODULE_SIZE)
    @content = content
    @size = size
  end

  def call
    qrcode = RQRCode::QRCode.new(@content)
    svg = qrcode.as_svg(
      color: '000',
      fill: 'fff',
      shape_rendering: 'crispEdges',
      module_size: @size,
      standalone: true,
      use_path: true,
      offset: OFFSET
    )
    make_responsive(svg)
  end

  private

  def make_responsive(svg)
    svg.sub(
      /<svg([^>]*?)\swidth="(\d+)"\s+height="(\d+)"([^>]*)>/,
      '<svg\1 width="100%" height="100%" viewBox="0 0 \2 \3" preserveAspectRatio="xMidYMid meet"\4>'
    )
  end
end
