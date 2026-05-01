# frozen_string_literal: true

require 'rails_helper'

describe 'imports.rake :reprocess' do
  let(:user) { create(:user) }
  let(:ids_file) do
    f = Tempfile.new(['ids', '.txt'])
    f.write(ids.join("\n"))
    f.flush
    f.path
  end

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('imports:reprocess')
  end

  before do
    Rake::Task['imports:reprocess'].reenable
    ActiveJob::Base.queue_adapter = :test
  end

  context 'with valid failed imports' do
    let!(:failed_a) do
      create(:import, user:, status: :failed, error_message: 'Unable to detect file format', source: nil).tap do |i|
        i.file.attach(io: StringIO.new('{"locations": []}'), filename: 'a.json', content_type: 'application/json')
      end
    end
    let!(:failed_b) do
      create(:import, user:, status: :failed, error_message: 'KMZ broken', source: nil).tap do |i|
        i.file.attach(io: StringIO.new('PK fake zip bytes'), filename: 'b.kmz', content_type: 'application/zip')
      end
    end
    let(:ids) { [failed_a.id, failed_b.id] }

    it 're-enqueues Import::ProcessJob for each id' do
      expect do
        Rake::Task['imports:reprocess'].invoke(ids_file)
      end.to have_enqueued_job(Import::ProcessJob).exactly(2).times
    end

    it 'resets failed imports back to created status with no error_message' do
      Rake::Task['imports:reprocess'].invoke(ids_file)

      expect(failed_a.reload).to have_attributes(status: 'created', error_message: nil)
      expect(failed_b.reload).to have_attributes(status: 'created', error_message: nil)
    end
  end

  context 'with non-failed imports in the list' do
    let!(:completed_import) do
      create(:import, user:, status: :completed).tap do |i|
        i.file.attach(io: StringIO.new('x'), filename: 'c.json')
      end
    end
    let(:ids) { [completed_import.id] }

    it 'skips them and does not enqueue' do
      expect do
        Rake::Task['imports:reprocess'].invoke(ids_file)
      end.not_to have_enqueued_job(Import::ProcessJob)
      expect(completed_import.reload.status).to eq('completed')
    end
  end

  context 'with imports whose file is no longer attached' do
    let!(:detached) { create(:import, user:, status: :failed) }
    let(:ids) { [detached.id] }

    it 'skips them and does not enqueue' do
      expect do
        Rake::Task['imports:reprocess'].invoke(ids_file)
      end.not_to have_enqueued_job(Import::ProcessJob)
    end
  end

  context 'with non-existent ids' do
    let(:ids) { [9_999_999] }

    it 'does not raise and does not enqueue' do
      expect do
        Rake::Task['imports:reprocess'].invoke(ids_file)
      end.not_to raise_error
      expect(Import::ProcessJob).not_to have_been_enqueued
    end
  end

  context 'in dry-run mode' do
    let!(:failed_import) do
      create(:import, user:, status: :failed).tap do |i|
        i.file.attach(io: StringIO.new('x'), filename: 'd.json')
      end
    end
    let(:ids) { [failed_import.id] }

    it 'does not reset status or enqueue jobs' do
      expect do
        Rake::Task['imports:reprocess'].invoke(ids_file, 'dry_run')
      end.not_to have_enqueued_job(Import::ProcessJob)
      expect(failed_import.reload.status).to eq('failed')
    end
  end
end
