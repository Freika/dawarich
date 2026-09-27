# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix port: the I18n reserved keys pinned in the Phoenix fixture' do
  it 'matches the live I18n::RESERVED_KEYS the gem defines' do
    fixture = JSON.parse(Rails.root.join('app-phoenix/test/fixtures/i18n_reserved_keys.json').read)

    expect(I18n::RESERVED_KEYS.map(&:to_s).sort).to eq(fixture['reserved_keys'])
  end
end
