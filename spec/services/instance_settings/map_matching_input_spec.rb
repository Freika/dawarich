# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceSettings::MapMatchingInput do
  before { InstanceSettings::Resolver.reset! }

  it 'normalizes a trailing slash from the Atlas URL' do
    input = described_class.new(atlas_url: ' https://atlas.example.com/base/ ')

    expect(input).to be_valid
    expect(input.values[:atlas_url]).to eq('https://atlas.example.com/base')
  end

  it 'accepts private HTTP endpoints used by self-hosters' do
    input = described_class.new(atlas_url: 'http://atlas:4567')

    expect(input).to be_valid
  end

  it 'rejects schemes other than HTTP and HTTPS' do
    input = described_class.new(atlas_url: 'file:///tmp/atlas')

    expect(input).not_to be_valid
  end

  it 'rejects embedded credentials' do
    input = described_class.new(atlas_url: 'https://user:secret@atlas.example.com')

    expect(input).not_to be_valid
  end

  it 'requires a URL when map matching is enabled' do
    input = described_class.new(map_matching_enabled: true, atlas_url: '')

    expect(input.errors).to include(I18n.t('admin.settings.update.atlas_url_required'))
  end

  it 'uses the saved URL when enabling separately' do
    InstanceSetting.create!(key: 'atlas_url', value: 'http://atlas:4567')
    InstanceSettings::Resolver.reset!

    input = described_class.new(map_matching_enabled: true)

    expect(input).to be_valid
  end
end
