# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::CreateJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform(json, user.id) }

    let(:file_path) { 'spec/fixtures/files/points/geojson_example.json' }
    let(:file) { File.open(file_path) }
    let(:json) { JSON.parse(file.read) }
    let(:user) { create(:user) }

    it 'creates a point' do
      expect { perform }.to change { Point.count }.by(6)
    end
  end
end
