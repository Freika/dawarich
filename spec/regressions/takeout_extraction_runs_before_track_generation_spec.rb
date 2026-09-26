# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Takeout extraction runs before track generation', type: :request do
  let(:user) { create(:user) }
  let(:fixture) { Rails.root.join('spec/fixtures/files/enhanced_import/google_phone_takeout_extractable.json') }
  let(:import) do
    create(:import, user: user, source: :google_phone_takeout, name: 'extractable.json').tap do |record|
      record.file.attach(io: File.open(fixture), filename: 'extractable.json', content_type: 'application/json')
    end
  end

  def run_generation
    perform_enqueued_jobs(only: Tracks::ParallelGeneratorJob)
    perform_enqueued_jobs(only: Tracks::TimeChunkProcessorJob)
  end

  def run_extraction
    perform_enqueued_jobs(only: EnhancedImport::ExtractJob)
  end

  def import_and_drain
    Imports::Create.new(user, import).call
    run_generation
    run_extraction
    run_generation
  end

  def source_modes
    TrackSegment.where(track: import.extracted_tracks, source: 'google_phone_takeout').pluck(:transportation_mode)
  end

  it 'lets the extraction own the activity tracks when generation is picked up first' do
    import_and_drain

    expect(import.reload.extraction_counts[:tracks]).to eq(2)
    expect(source_modes).to contain_exactly('driving', 'walking')
  end

  it 'keeps the source modes when the import is reverted and re-extracted' do
    import_and_drain
    sign_in user

    delete import_extraction_path(import)
    perform_enqueued_jobs(only: EnhancedImport::DestroyJob)
    post import_extraction_path(import)
    run_generation
    run_extraction

    expect(Tracks::ParallelGeneratorJob).to have_been_enqueued.with(user.id, hash_including(untracked_only: true))

    run_generation

    expect(import.reload.extraction_counts[:tracks]).to eq(2)
    expect(source_modes).to contain_exactly('driving', 'walking')
  end
end
