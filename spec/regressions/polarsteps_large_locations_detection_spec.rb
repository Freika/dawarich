# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Polarsteps locations detection beyond the JSON sample limit' do
  it 'detects a large locations export from its file header' do
    locations = Array.new(1000) { |index| { lat: 1.0, lon: 2.0, time: 1_700_000_000 + index } }
    content = { locations: locations }.to_json
    expect(content.bytesize).to be > Imports::SourceDetector::MAX_DETECTION_BYTES

    Tempfile.create(['locations', '.json']) do |file|
      file.write(content)
      file.flush

      expect(Imports::SourceDetector.new_from_file_header(file.path).detect_source!).to eq(:polarsteps)
    end
  end
end
