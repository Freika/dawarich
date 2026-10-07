# frozen_string_literal: true

require 'json'

abort 'Ruby 3.4.9 is required' unless RUBY_VERSION == '3.4.9'

mapping = {}
(0..0x10ffff).each do |codepoint|
  next if (0xd800..0xdfff).cover?(codepoint)

  char = codepoint.chr(Encoding::UTF_8)
  lower = char.downcase
  mapping[codepoint] = lower if lower != char
end

path = File.expand_path('../../priv/ruby_downcase.json', __dir__)
File.write(path, "#{JSON.generate({ ruby: RUBY_VERSION, mapping: mapping })}\n")
