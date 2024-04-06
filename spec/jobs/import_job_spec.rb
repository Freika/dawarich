require 'rails_helper'

RSpec.describe ImportJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform(user.id, import.id) }

    let(:file_path) { 'spec/fixtures/files/owntracks/export.json' }
    let(:file) { fixture_file_upload(file_path) }
    let(:user) { create(:user) }
    let(:import) { create(:import, user: user, file: file, name: File.basename(file.path)) }

    it 'creates points' do
      expect { perform }.to change { Point.count }.by(8)
    end

    it 'calls StatCreatingJob' do
      expect(StatCreatingJob).to receive(:perform_later).with(user.id)

      perform
    end
  end
end
