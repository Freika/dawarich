# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'zip'

RSpec.describe 'Scoped export backup restoration' do
  let(:owner) { create(:user) }
  let(:restored_owner) { create(:user) }
  let(:start_at) { Time.utc(2025, 1, 1) }
  let(:end_at) { start_at + 1.day }

  def payload_count(export)
    Zip::InputStream.open(StringIO.new(export.reload.file.download)) do |zip|
      zip.get_next_entry
      JSON.parse(zip.read)['features'].length
    end
  end

  def backup(export, files)
    [Users::ExportData::Imports.new(export.user, files).call,
     Users::ExportData::Exports.new(export.user, files).call.find { |row| row['name'] == export.name }]
  end

  def source_export
    import = create(:import, user: owner)
    create(:point, user: owner, import: import, timestamp: start_at.to_i + 60)
    export = owner.exports.create!(name: 'filtered.json', file_format: :json, start_at: start_at, end_at: end_at,
                                   import_id: import.id)
    export.process!
    export.reload
  end

  it 'roundtrips the file and source identity through the actual V2 restore handler without re-enqueueing it' do
    export = source_export
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      files = root.join('files').tap(&:mkpath)
      imports, row = backup(export, files)
      root.join('manifest.json').write({ format_version: 2 }.to_json)
      root.join('imports.jsonl').write(imports.map(&:to_json).join("\n"))
      root.join('exports.jsonl').write(row.to_json)
      clear_enqueued_jobs
      Users::ImportData::V2Handler.new(restored_owner, root, Hash.new(0)).process
      restored = restored_owner.exports.sole
      expect(restored.file.download).to eq(export.file.download)
      expect(restored.import).to eq(restored_owner.imports.sole)
      expect(restored.import_id).not_to eq(export.import_id)
      expect(enqueued_jobs.select { |job| job[:job] == ExportJob }).to be_empty
      create(:point, user: restored_owner, import: restored.import, timestamp: start_at.to_i + 60)
      create(:point, user: restored_owner, timestamp: start_at.to_i + 120)
      restored.process!
      expect(payload_count(restored)).to eq(1)
    end
  end

  it 'restores a removed source as unavailable and never widens a regenerated export' do
    export = source_export
    export.import.destroy!
    Dir.mktmpdir do |directory|
      files = Pathname(directory)
      _, row = backup(export.reload, files)
      expect(Users::ImportData::Exports.new(restored_owner, [row], files).call).to eq([1, 1])
      restored = restored_owner.exports.sole
      expect(restored.file.download).to eq(export.file.download)
      expect(restored).to be_import_scope_unavailable
      create(:point, user: restored_owner, timestamp: start_at.to_i + 60)
      restored.process!
      expect(payload_count(restored)).to eq(0)
    end
  end

  it 'fails closed on legacy numeric IDs even when that ID belongs to an unrelated target import' do
    unrelated = create(:import, user: restored_owner)
    Dir.mktmpdir do |directory|
      data = { 'name' => 'legacy.json', 'file_format' => 'json', 'status' => 'completed',
               'import_id' => unrelated.id, 'start_at' => start_at, 'end_at' => end_at }
      expect(Users::ImportData::Exports.new(restored_owner, [data], Pathname(directory)).call.first).to eq(1)
      restored = restored_owner.exports.sole
      expect(restored.import_id).to be_nil
      expect(restored).to be_import_scope_unavailable
      create(:point, user: restored_owner, import: unrelated, timestamp: start_at.to_i + 60)
      restored.process!
      expect(payload_count(restored)).to eq(0)
    end
  end

  it 'retains a missing source marker through a second backup and restore' do
    export = source_export
    export.import.destroy!
    Dir.mktmpdir do |directory|
      files = Pathname(directory)
      _, row = backup(export.reload, files)
      Users::ImportData::Exports.new(restored_owner, [row], files).call
      _, second_row = backup(restored_owner.exports.sole, files)
      third_owner = create(:user)
      Users::ImportData::Exports.new(third_owner, [second_row], files).call
      expect(third_owner.exports.sole).to be_import_scope_unavailable
    end
  end

  [nil, {}, { 'reference' => { 'name' => 'missing' } }].each do |scope|
    it "keeps malformed scope #{scope.inspect} closed instead of falling back to all sources" do
      Dir.mktmpdir do |directory|
        data = { 'name' => 'invalid-scope.json', 'file_format' => 'json', 'status' => 'completed',
                 'import_scope' => scope, 'start_at' => start_at, 'end_at' => end_at }
        Users::ImportData::Exports.new(restored_owner, [data], Pathname(directory)).call
        restored = restored_owner.exports.sole
        expect(restored).to be_import_scope_unavailable
        create(:point, user: restored_owner, timestamp: start_at.to_i + 60)
        restored.process!
        expect(payload_count(restored)).to eq(0)
      end
    end
  end

  it 'reuses an existing exact source identity without losing timestamp microseconds' do
    export = source_export
    original = export.import
    original.update!(created_at: Time.iso8601('2025-01-01T00:00:00.123456Z'))
    target_import = create(:import, user: restored_owner, name: original.name,
      source: original.source, created_at: original.created_at)
    Dir.mktmpdir do |directory|
      files = Pathname(directory)
      imports, row = backup(export.reload, files)
      Users::ImportData::Imports.new(restored_owner, imports, files).call
      Users::ImportData::Exports.new(restored_owner, [row], files).call
      expect(restored_owner.imports.count).to eq(1)
      expect(restored_owner.exports.sole.import_id).to eq(target_import.id)
    end
  end

  it 'leaves legacy unfiltered exports unfiltered' do
    Dir.mktmpdir do |directory|
      data = { 'name' => 'unfiltered.json', 'file_format' => 'json', 'status' => 'completed',
               'import_id' => nil, 'start_at' => start_at, 'end_at' => end_at }
      Users::ImportData::Exports.new(restored_owner, [data], Pathname(directory)).call
      restored = restored_owner.exports.sole
      expect(restored).not_to be_import_scoped
      create(:point, user: restored_owner, timestamp: start_at.to_i + 60)
      restored.process!
      expect(payload_count(restored)).to eq(1)
    end
  end

  it 'also restores scoped records and files through the legacy V1 handler' do
    export = source_export
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      files = root.join('files').tap(&:mkpath)
      imports, row = backup(export, files)
      root.join('data.json').write({ imports: imports, exports: [row] }.to_json)
      Users::ImportData::V1Handler.new(restored_owner, root, Hash.new(0)).process
      restored = restored_owner.exports.sole
      expect(restored.import).to eq(restored_owner.imports.sole)
      expect(restored.file.download).to eq(export.file.download)
    end
  end
  %w[created processing].each do |status|
    it "makes restored #{status} work explicitly retryable instead of orphaning or enqueueing it mid-restore" do
      Dir.mktmpdir do |directory|
        data = { 'name' => 'unfinished.json', 'file_format' => 'json', 'status' => status,
                 'start_at' => start_at, 'end_at' => end_at }
        clear_enqueued_jobs
        Users::ImportData::Exports.new(restored_owner, [data], Pathname(directory)).call
        expect(restored_owner.exports.sole).to be_failed
        expect(restored_owner.exports.sole.error_message).to include('unfinished in the backup')
        expect(enqueued_jobs.select { |job| job[:job] == ExportJob }).to be_empty
      end
    end
  end
end
