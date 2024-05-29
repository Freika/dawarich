# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Overland::BatchCreatingJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform(json, user.id) }

    let(:file_path) { 'spec/fixtures/files/overland/geodata.json' }
    let(:file) { File.open(file_path) }
    let(:json) { JSON.parse(file.read) }
    let(:user) { create(:user) }

    it 'creates a location' do
      expect { perform }.to change { Point.count }.by(1)
    end

    it 'creates a point with the correct user_id' do
      perform

      expect(Point.last.user_id).to eq(user.id)
    end

    context 'when point already exists' do
      it 'does not create a point' do
        perform

        expect { perform }.not_to(change { Point.count })
      end
    end
  end
end
