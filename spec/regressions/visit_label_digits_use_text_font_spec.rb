# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map label font fallback' do
  it 'uses a text font before every emoji font while preserving emoji fallbacks' do
    stylesheet = Rails.root.join('app/assets/stylesheets/maps_maplibre.css').read
    label_rule = stylesheet.match(/\.map-html-label\s*\{([^}]+)\}/m)[1]
    families = label_rule.match(/font-family:\s*([^;]+);/m)[1].split(',').map(&:strip)
    text_font_index = families.index('sans-serif')

    expect(text_font_index).not_to be_nil
    ['"Apple Color Emoji"', '"Segoe UI Emoji"', '"Noto Color Emoji"'].each do |emoji_font|
      expect(families).to include(emoji_font)
      expect(text_font_index).to be < families.index(emoji_font)
    end
  end
end
