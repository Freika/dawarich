require 'rails_helper'

RSpec.describe Overland::BatchCreatingJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform(json) }

    let(:file_path) { 'spec/fixtures/files/overland/geodata.json' }
    let(:file) { File.open(file_path) }
    let(:json) { JSON.parse(file.read) }

    it 'creates a location' do
      expect { perform }.to change { Point.count }.by(1)
    end
  end
end
