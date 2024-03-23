require 'rails_helper'

RSpec.describe OwnTracks::ExportParser do
  describe '#call' do
    subject(:parser) { described_class.new(file_path, import_id).call }

    let(:file_path) { 'spec/fixtures/owntracks_export.json' }
    let(:import_id) { nil }

    context 'when file exists' do
      it 'creates points' do
        expect { parser }.to change { Point.count }.by(8)
      end
    end

    context 'when file does not exist' do
      let(:file_path) { 'spec/fixtures/not_found.json' }

      it 'raises error' do
        expect { parser }.to raise_error('File not found')
      end
    end
  end
end
