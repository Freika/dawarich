# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixture: the I18n gem reserved interpolation keys' do
  it 'writes app-phoenix/test/fixtures/i18n_reserved_keys.json' do
    fixture = { reserved_keys: I18n::RESERVED_KEYS.map(&:to_s).sort }
    FixtureRecording.verify(
      Rails.root.join('app-phoenix/test/fixtures/i18n_reserved_keys.json'),
      "#{JSON.pretty_generate(fixture)}\n"
    )
  end
end
