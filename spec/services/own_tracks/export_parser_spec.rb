require 'rails_helper'

RSpec.describe OwnTracks::ExportParser do
  describe '#call' do
    subject(:parser) { described_class.new(import.id).call }

    let(:file_path) { 'spec/fixtures/owntracks_export.json' }
    let(:file) { fixture_file_upload(file_path) }
    let(:user) { create(:user) }
    let(:import) { create(:import, user: user, file: file, name: File.basename(file.path)) }

    context 'when file exists' do
      it 'creates points' do
        expect { parser }.to change { Point.count }.by(8)
      end
    end
  end
end
