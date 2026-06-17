# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InferredPoints::Importer do
  let(:user) { create(:user) }
  let(:base) { Time.zone.local(2024, 5, 1, 11, 0, 0) }
  let(:geojson) { { type: 'FeatureCollection', features: [] }.to_json }

  let(:points) do
    [
      build(:point, user: user, source: :inferred, timestamp: base.to_i, import: nil),
      build(:point, user: user, source: :inferred, timestamp: (base + 5.minutes).to_i, import: nil)
    ]
  end

  subject(:importer) do
    described_class.new(
      user: user,
      points: points,
      geojson: geojson,
      import_name: 'Gap-fill test',
      filename_prefix: 'gapfill'
    )
  end

  it 'persists the points to a new completed geojson import' do
    expect { importer.call }.to change { user.points.count }.by(2)

    import = user.imports.order(:created_at).last
    expect(import.source).to eq('geojson')
    expect(import.status).to eq('completed')
    expect(user.points.where(import_id: import.id).count).to eq(2)
  end

  it 'does not enqueue Import::ProcessJob' do
    expect { importer.call }.not_to have_enqueued_job(Import::ProcessJob)
  end

  it 'sets points_count and processed on the import' do
    import = importer.call

    expect(import.points_count).to eq(2)
    expect(import.processed).to eq(2)
  end

  it 'attaches the geojson payload as a file' do
    import = importer.call

    expect(import.file).to be_attached
    expect(import.file.filename.to_s).to eq("gapfill_#{import.id}.geojson")
    expect(import.file.content_type).to eq('application/json')
  end

  it 'enqueues a bulk full rebuild of the affected window' do
    expect { importer.call }.to have_enqueued_job(Tracks::ParallelGeneratorJob)
      .with(user.id, hash_including(mode: :bulk, untracked_only: false))
  end

  it 'expands the regeneration window to overlapping tracks' do
    track = create(
      :track,
      user: user,
      start_at: base - 2.hours,
      end_at: base + 2.hours
    )

    captured = nil
    expect { importer.call }.to have_enqueued_job(Tracks::ParallelGeneratorJob)
      .with { |_user_id, opts| captured = opts }

    expect(captured[:start_at]).to be <= track.start_at
    expect(captured[:end_at]).to be >= track.end_at
  end

  context 'when points is empty' do
    let(:points) { [] }

    it 'creates no import and enqueues no job' do
      expect { importer.call }.not_to change(Import, :count)
      expect(importer.call).to be_nil
      expect(Tracks::ParallelGeneratorJob).not_to have_been_enqueued
    end
  end
end
