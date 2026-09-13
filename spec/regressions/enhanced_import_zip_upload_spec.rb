# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Extraction reads a single-entry archive upload' do
  let(:user) { create(:user) }
  let(:source_json) { Rails.root.join('spec/fixtures/files/enhanced_import/polarsteps_steps_array.json') }
  let(:zip_path) { Rails.root.join("tmp/enhanced_import_#{SecureRandom.hex(4)}.zip") }

  before do
    Zip::File.open(zip_path, create: true) do |zip|
      zip.add('locations.json', source_json)
    end
  end

  after { FileUtils.rm_f(zip_path) }

  it 'unwraps the archive instead of feeding zip bytes to the parser' do
    import = create(:import, user: user, source: :polarsteps, name: "zipped-#{rand(10_000)}.zip")
    import.file.attach(io: File.open(zip_path), filename: 'export.zip', content_type: 'application/zip')

    EnhancedImport::ExtractJob.new.perform(import.id)

    expect(import.reload.additional_data_extraction_completed?).to be true
    expect(import.extraction_counts[:visits]).to eq(2)
  end
end
