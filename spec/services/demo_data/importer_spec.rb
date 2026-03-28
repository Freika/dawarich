# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DemoData::Importer do
  subject(:importer) { described_class.new(user) }

  let(:user) { create(:user) }

  describe '#call' do
    it 'creates a demo import' do
      result = importer.call

      expect(result[:status]).to eq(:created)
      expect(result[:import]).to be_persisted
      expect(result[:import].demo).to be true
      expect(result[:import].name).to eq('Demo Data (Berlin)')
      expect(result[:import].source).to eq('geojson')
    end

    it 'attaches a JSON file' do
      result = importer.call

      expect(result[:import].file).to be_attached
      expect(result[:import].file.filename.to_s).to eq('demo_data.json')
    end

    it 'enqueues the import processing job' do
      expect { importer.call }.to have_enqueued_job(Import::ProcessJob)
    end

    context 'when demo data already exists' do
      before { create(:import, user: user, demo: true, name: 'Demo Data (Berlin)') }

      it 'returns exists status' do
        result = importer.call

        expect(result[:status]).to eq(:exists)
      end

      it 'does not create a new import' do
        expect { importer.call }.not_to change(Import, :count)
      end
    end

    context 'when user is on trial with max imports' do
      let(:user) { create(:user, :trial) }

      before do
        5.times { |i| create(:import, user: user, name: "import_#{i}") }
      end

      it 'still creates a demo import bypassing trial limits' do
        result = importer.call

        expect(result[:status]).to eq(:created)
        expect(result[:import]).to be_persisted
      end
    end
  end
end
