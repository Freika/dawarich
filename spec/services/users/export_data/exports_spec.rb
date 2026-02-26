# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Exports, type: :service do
  let(:user) { create(:user) }
  let(:files_directory) { Rails.root.join('tmp/test_export_files') }
  let(:service) { described_class.new(user, files_directory) }

  subject { service.call }

  before do
    FileUtils.mkdir_p(files_directory)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  after do
    FileUtils.rm_rf(files_directory) if File.directory?(files_directory)
  end

  describe '#call' do
    context 'when user has no exports' do
      it 'returns an empty array' do
        expect(subject).to eq([])
      end
    end

    context 'when user has exports without files' do
      let!(:export_without_file) do
        create(:export,
               user: user,
               name: 'Test Export',
               file_format: :json,
               file_type: :points,
               status: :completed)
      end

      it 'returns export data without file information' do
        expect(subject.size).to eq(1)

        export_data = subject.first

        expect(export_data).to include(
          'name' => 'Test Export',
          'file_format' => 'json',
          'file_type' => 'points',
          'status' => 'completed'
        )
        expect(export_data).not_to have_key('user_id')
        expect(export_data).not_to have_key('id')

        expect(export_data['file_name']).to be_nil
        expect(export_data['original_filename']).to be_nil
      end
    end

    context 'when user has exports with attached files' do
      let(:file_content) { 'export file content' }
      let(:blob) { create_blob(filename: 'export_data.json', content_type: 'application/json') }
      let!(:export_with_file) do
        export = create(:export, user: user, name: 'Export with File')
        export.file.attach(blob)
        export
      end

      before do
        # Mock the file download - exports use direct file access
        allow(File).to receive(:open).and_call_original
        allow(File).to receive(:write).and_call_original
      end

      it 'returns export data with file information' do
        export_data = subject.first

        expect(export_data['name']).to eq('Export with File')
        expect(export_data['file_name']).to eq("export_#{export_with_file.id}_export_data.json")
        expect(export_data['original_filename']).to eq('export_data.json')
        expect(export_data['file_size']).to be_present
        expect(export_data['content_type']).to eq('application/json')
      end
    end

    context 'with multiple users' do
      let(:other_user) { create(:user) }
      let!(:user_export) { create(:export, user: user, name: 'User Export') }
      let!(:other_user_export) { create(:export, user: other_user, name: 'Other User Export') }

      it 'only returns exports for the specified user' do
        expect(subject.size).to eq(1)
        expect(subject.first['name']).to eq('User Export')
      end
    end
  end

  private

  def create_blob(filename: 'test.txt', content_type: 'text/plain')
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('test content'),
      filename: filename,
      content_type: content_type
    )
  end
end
