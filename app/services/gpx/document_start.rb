# frozen_string_literal: true

# Positions an IO at the start of the XML document, preserving a byte order
# mark so Nokogiri can detect the encoding from it. Without a BOM, any preamble
# before the first '<' is skipped.
module Gpx::DocumentStart
  BOMS = [
    "\xEF\xBB\xBF".b,
    "\xFE\xFF".b,
    "\xFF\xFE".b,
    "\x00\x00\xFE\xFF".b,
    "\xFF\xFE\x00\x00".b
  ].freeze

  def self.seek(io)
    prefix = io.read(256) || ''
    offset = BOMS.any? { |bom| prefix.start_with?(bom) } ? 0 : prefix.index('<') || 0
    io.seek(offset)
  end
end
