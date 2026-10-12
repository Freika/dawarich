# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Polarsteps extraction reads the shape the detector actually accepts' do
  let(:user) { create(:user) }

  def import_with(path)
    import = create(:import, user: user, source: :polarsteps, name: "polarsteps-#{rand(10_000)}.json")
    import.file.attach(
      io: File.open(Rails.root.join(path)),
      filename: File.basename(path),
      content_type: 'application/json'
    )
    import
  end

  it 'extracts visits from a bare array of steps' do
    import = import_with('spec/fixtures/files/enhanced_import/polarsteps_steps_array.json')

    EnhancedImport::ExtractJob.new.perform(import.id)

    expect(import.reload.additional_data_extraction_completed?).to be true
    expect(import.extraction_counts[:visits]).to eq(2)
    expect(Place.where(import_id: import.id).pluck(:name)).to include('Tokyo, Japan', 'Kyoto, Japan')
  end

  it 'completes without artifacts for a locations-only GPS trail' do
    trail = Rails.root.join('tmp/polarsteps_locations_only.json')
    trail.write({ 'locations' => [{ 'lat' => 51.34, 'lon' => 12.37, 'time' => 1_735_689_600 }] }.to_json)
    import = import_with(trail.relative_path_from(Rails.root).to_s)

    expect { EnhancedImport::ExtractJob.new.perform(import.id) }.not_to raise_error

    expect(import.reload.additional_data_extraction_completed?).to be true
    expect(import.extraction_counts[:visits].to_i).to eq(0)
  ensure
    FileUtils.rm_f(trail)
  end
end
