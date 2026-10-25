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

  it 'reuses exact SVGs without serializing or digesting arguments' do
    expected = Icons::Icon.new(name: 'map', library: RailsIcons.configuration.default_library,
                               arguments: { class: 'w-4 h-4', data: { label: 'Map' } }).svg
    allow(Icons::Icon).to receive(:new).and_call_original
    expect(Marshal).not_to receive(:dump)
    expect(Digest::SHA256).not_to receive(:hexdigest)

    2.times do
      result = helper.icon('map', class: 'w-4 h-4', data: { label: 'Map' })
      expect(result).to eq(expected)
      expect(result).to be_html_safe
    end
    expect(Icons::Icon).to have_received(:new).once
  end

  it 'bounds cached argument combinations and renders evicted entries identically' do
    stub_const('RailsIconsCache::MAX_ENTRIES', 3)
    allow(Icons::Icon).to receive(:new).and_call_original
    first = helper.icon('map', class: 'first')
    3.times { |index| helper.icon('map', class: "other-#{index}") }

    expect(helper.icon('map', class: 'first')).to eq(first)
    expect(Icons::Icon).to have_received(:new).exactly(5).times
  end

  it 'snapshots mutable nested arguments and separates colliding hashes and attribute order' do
    expect(Marshal).not_to receive(:dump)
    allow(Icons::Icon).to receive(:new).and_call_original
    labels = { label: +'before' }
    first = helper.icon('map', data: labels)
    labels[:label].replace('after')
    expect(helper.icon('map', data: labels)).not_to eq(first)
    expect(helper.icon('map', data: { label: 'before' })).to eq(first)
    expect(Icons::Icon).to have_received(:new).twice

    collision = Class.new(String) { def hash = 1 }
    expect(helper.icon('map', class: collision.new('small')))
      .not_to eq(helper.icon('map', class: collision.new('large')))

    [{ class: 'small', title: 'Map' }, { title: 'Map', class: 'small' }].each do |arguments|
      expected = Icons::Icon.new(name: 'map', library: RailsIcons.configuration.default_library,
                                 arguments: arguments).svg
      expect(helper.icon('map', **arguments)).to eq(expected)
    end
  end
end
