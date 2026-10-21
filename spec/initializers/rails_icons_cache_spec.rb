# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'rails_icons render cache', type: :helper do
  before { RailsIconsCache::STORE.clear }

  it 'reads and parses each icon once per name and arguments' do
    allow(Icons::Icon).to receive(:new).and_call_original

    first = helper.icon('map', class: 'w-4 h-4')
    second = helper.icon('map', class: 'w-4 h-4')

    expect(second).to eq(first)
    expect(first).to be_html_safe
    expect(Icons::Icon).to have_received(:new).once
  end

  it 'keeps different arguments apart' do
    expect(helper.icon('map', class: 'w-4 h-4')).not_to eq(helper.icon('map', class: 'w-6 h-6'))
  end
end
