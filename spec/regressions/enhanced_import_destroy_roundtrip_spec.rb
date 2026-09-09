# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enhanced import extraction can be undone' do
  let(:user) { create(:user) }
  let(:fixture_path) { Rails.root.join('spec/fixtures/files/enhanced_import/polarsteps_segments_minimal.json') }

  let(:import) do
    import = create(:import, user: user, source: :polarsteps, name: "undo-#{rand(10_000)}.json")
    import.file.attach(
      io: File.open(fixture_path),
      filename: File.basename(fixture_path),
      content_type: 'application/json'
    )
    import
  end

  it 'stamps every artifact with the import and removes them again' do
    EnhancedImport::ExtractJob.new.perform(import.id)
    import.reload

    expect(import.additional_data_extraction_completed?).to be true
    expect(Visit.where(import_id: import.id).count).to be > 0
    expect(Place.where(import_id: import.id).count).to be > 0

    expect { EnhancedImport::Destroy.new(import).call }
      .to change { Visit.where(import_id: import.id).count }.to(0)
      .and change { Place.where(import_id: import.id).count }.to(0)

    import.reload
    expect(import.additional_data_extraction_not_attempted?).to be true
    expect(import.extraction_counts).to eq({})
  end

  it 'leaves the imported points untouched' do
    EnhancedImport::ExtractJob.new.perform(import.id)

    expect { EnhancedImport::Destroy.new(import.reload).call }.not_to(change(Point, :count))
  end
end
