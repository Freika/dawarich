# frozen_string_literal: true

module Imports
  module XmlAmpersandEscaping
    extend ActiveSupport::Concern

    CDATA_SECTION = /(<!\[CDATA\[.*?\]\]>)/m
    AMPERSAND = /&(?:([a-zA-Z][a-zA-Z0-9]*|#\d+|#x\h+);)?/
    PREDEFINED_ENTITIES = %w[amp lt gt quot apos].freeze

    private

    def escape_raw_ampersands(content)
      content.split(CDATA_SECTION).map do |segment|
        segment.start_with?('<![CDATA[') ? segment : escape_ampersands_in_segment(segment)
      end.join
    end

    def escape_ampersands_in_segment(segment)
      segment.gsub(AMPERSAND) do
        reference = Regexp.last_match(1)

        if reference.nil?
          '&amp;'
        elsif legal_reference?(reference)
          "&#{reference};"
        else
          "&amp;#{reference};"
        end
      end
    end

    def legal_reference?(reference)
      if reference.start_with?('#x')
        legal_codepoint?(reference[2..].to_i(16))
      elsif reference.start_with?('#')
        legal_codepoint?(reference[1..].to_i)
      else
        PREDEFINED_ENTITIES.include?(reference)
      end
    end

    def legal_codepoint?(codepoint)
      codepoint == 0x9 || codepoint == 0xA || codepoint == 0xD ||
        (0x20..0xD7FF).cover?(codepoint) ||
        (0xE000..0xFFFD).cover?(codepoint) ||
        (0x10000..0x10FFFF).cover?(codepoint)
    end
  end
end
