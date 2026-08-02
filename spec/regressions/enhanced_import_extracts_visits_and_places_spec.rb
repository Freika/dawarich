# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enhanced import extracts visits and places' do
  let(:user) { create(:user) }

  shared_examples 'an adapter that emits one visit and one place' do
    it 'creates the place with an external_place_id' do
      EnhancedImport::ExtractJob.new.perform(import.id)
      place = Place.last
      expect(place).to be_present
      expect(place.geodata['external_place_id']).to start_with(expected_place_id_prefix)
    end

    it 'creates the visit linked to the place' do
      EnhancedImport::ExtractJob.new.perform(import.id)
      visit = Visit.last
      expect(visit).to be_present
      expect(visit.user_id).to eq(user.id)
      expect(visit.place_id).to eq(Place.last.id)
      expect(visit.duration).to be > 0
    end

    it 'records counts on the import' do
      EnhancedImport::ExtractJob.new.perform(import.id)
      expect(import.reload.extraction_counts[:visits]).to eq(1)
      expect(import.reload.extraction_counts[:places]).to eq(1)
      expect(import.reload.additional_data_extraction_status).to eq('completed')
    end
  end

  context 'with a Google phone takeout file' do
    let(:expected_place_id_prefix) { 'google:' }
    let(:fixture_path) { Rails.root.join('spec/fixtures/files/enhanced_import/google_phone_takeout_minimal.json') }
    let(:import) { build_import_with_file(:google_phone_takeout, fixture_path) }

    include_examples 'an adapter that emits one visit and one place'
  end

  context 'with a Google semantic history file' do
    let(:expected_place_id_prefix) { 'google:' }
    let(:fixture_path) { Rails.root.join('spec/fixtures/files/enhanced_import/google_semantic_history_minimal.json') }
    let(:import) { build_import_with_file(:google_semantic_history, fixture_path) }

    include_examples 'an adapter that emits one visit and one place'
  end

  context 'with a Polarsteps export' do
    let(:expected_place_id_prefix) { 'polarsteps:' }
    let(:fixture_path) { Rails.root.join('spec/fixtures/files/enhanced_import/polarsteps_segments_minimal.json') }
    let(:import) { build_import_with_file(:polarsteps, fixture_path) }

    include_examples 'an adapter that emits one visit and one place'
  end

  def build_import_with_file(source, path)
    import = create(:import, user: user, source: source, name: "test-#{source}-#{rand(10_000)}.json")
    import.file.attach(
      io: File.open(path),
      filename: File.basename(path),
      content_type: 'application/json'
    )
    import
  end
end
