# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLinks::PhotoSources do
  subject(:enabled) { described_class.new(link).enabled }

  let(:link) { build(:shared_link, settings: settings) }

  context 'with a legacy shared link' do
    let(:settings) { { 'show_photos' => true } }

    it 'preserves the original automatic integration selection' do
      expect(enabled).to be_nil
    end
  end

  context 'with explicitly selected sources' do
    let(:settings) do
      {
        'show_photos' => true,
        'show_photoprism' => false,
        'show_immich' => true
      }
    end

    it 'returns only enabled sources' do
      expect(enabled).to eq(['immich'])
    end
  end

  context 'with photos disabled' do
    let(:settings) do
      {
        'show_photos' => false,
        'show_photoprism' => false,
        'show_immich' => false
      }
    end

    it 'returns no sources' do
      expect(enabled).to eq([])
    end
  end
end
