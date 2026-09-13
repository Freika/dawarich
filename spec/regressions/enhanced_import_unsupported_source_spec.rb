# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enhanced import for unsupported sources is not offered' do
  let(:user) { create(:user) }

  it 'marks KML imports as unsupported on creation' do
    import = create(:import, user: user, source: :kml)
    expect(import.additional_data_extraction_unsupported?).to be true
  end

  it 'reports a KML import as not supported by the translator' do
    import = build(:import, user: user, source: :kml)
    expect(import.additional_data_extraction_supported?).to be false
  end

  it 'reports the sources with a real adapter as supported' do
    %i[google_phone_takeout google_semantic_history polarsteps gpx].each do |src|
      import = build(:import, user: user, source: src)
      expect(import.additional_data_extraction_supported?).to be(true), "expected #{src} supported"
    end
  end

  it 'does not offer extraction for Google Records, whose export carries no visit metadata' do
    import = build(:import, user: user, source: :google_records)
    expect(import.additional_data_extraction_supported?).to be false
  end

  it 'translator returns no items for an unsupported source' do
    import = create(:import, user: user, source: :kml)
    items = EnhancedImport::Translator.new(import).translate.to_a
    expect(items).to be_empty
  end
end
