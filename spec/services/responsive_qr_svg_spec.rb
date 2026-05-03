# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ResponsiveQrSvg do
  describe '.call' do
    let(:content) { 'https://example.com/some/long/url?token=' + ('a' * 80) }

    it 'returns a single <svg> element' do
      svg = described_class.call(content)
      expect(svg.scan(/<svg\b/).length).to eq(1)
    end

    it 'replaces fixed pixel width/height with 100% so the SVG scales to its container' do
      svg = described_class.call(content)
      expect(svg).to match(/<svg[^>]*\swidth="100%"/)
      expect(svg).to match(/<svg[^>]*\sheight="100%"/)
      expect(svg).not_to match(/<svg[^>]*\swidth="\d+"/)
      expect(svg).not_to match(/<svg[^>]*\sheight="\d+"/)
    end

    it 'injects a viewBox matching the original pixel dimensions so the QR keeps its aspect ratio' do
      raw = RQRCode::QRCode.new(content).as_svg(
        color: '000', fill: 'fff', shape_rendering: 'crispEdges',
        module_size: 6, standalone: true, use_path: true, offset: 5
      )
      pixel_size = raw.match(/<svg[^>]*\swidth="(\d+)"/)[1]

      svg = described_class.call(content)
      expect(svg).to match(/viewBox="0 0 #{pixel_size} #{pixel_size}"/)
    end

    it 'preserves the QR path data so the encoded content is unchanged' do
      svg = described_class.call(content)
      expect(svg).to match(/<path d="M0 0h7v7h-7z/) # finder pattern is the canonical QR start
    end

    it 'accepts a custom module size' do
      small = described_class.call(content, size: 3)
      large = described_class.call(content, size: 6)

      small_box = small.match(/viewBox="0 0 (\d+) \d+"/)[1].to_i
      large_box = large.match(/viewBox="0 0 (\d+) \d+"/)[1].to_i

      expect(large_box).to be > small_box
    end
  end
end
