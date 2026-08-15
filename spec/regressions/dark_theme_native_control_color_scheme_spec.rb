# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'DaisyUI theme color-scheme in compiled CSS' do
  let(:css) { Rails.root.join('app/assets/builds/tailwind.css').read }

  def theme_rule(css, theme)
    css[/\[data-theme=#{Regexp.escape(theme)}\]\{([^}]*)\}/, 1]
  end

  it 'declares color-scheme:dark on the dark theme so native controls render legibly' do
    rule = theme_rule(css, 'dawarich-dark')

    expect(rule).to be_present, 'no [data-theme=dawarich-dark] rule found in compiled CSS'
    expect(rule).to include('color-scheme:dark'),
                    'dawarich-dark must set color-scheme:dark, otherwise native date/time picker ' \
                    'indicators keep their light-mode glyph and disappear on the dark background'
  end

  it 'declares color-scheme:light on the light theme' do
    rule = theme_rule(css, 'dawarich')

    expect(rule).to be_present, 'no [data-theme=dawarich] rule found in compiled CSS'
    expect(rule).to include('color-scheme:light')
  end
end
