# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enhanced import extracts named frequent places' do
  let(:user) { create(:user) }
  let(:fixture_path) do
    Rails.root.join('spec/fixtures/files/enhanced_import/google_phone_takeout_with_frequent_places.json')
  end
  let(:import) do
    imp = create(:import, user: user, source: :google_phone_takeout)
    imp.file.attach(
      io: File.open(fixture_path),
      filename: 'frequent.json',
      content_type: 'application/json'
    )
    imp
  end

  it 'creates a Place row per frequentPlace with the user-facing label' do
    EnhancedImport::ExtractJob.new.perform(import.id)

    home = Place.find_by("geodata ->> 'external_place_id' = ?", 'google:ChIJ_HOME_FREQUENT')
    work = Place.find_by("geodata ->> 'external_place_id' = ?", 'google:ChIJ_WORK_FREQUENT')

    expect(home).to be_present
    expect(home.name).to eq('Home')
    expect(work).to be_present
    expect(work.name).to eq('Work')
  end

  it 'records the frequentPlaces in the import counts' do
    EnhancedImport::ExtractJob.new.perform(import.id)
    expect(import.reload.extraction_counts[:places]).to be >= 2
  end
end
