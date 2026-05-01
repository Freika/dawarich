# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Polarsteps::Importer do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:, source: :polarsteps) }

  describe '#call' do
    context 'with official locations.json format' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/polarsteps/locations.json').to_s }

      before { described_class.new(import, user.id, file_path).call }

      it 'creates one point per location' do
        expect(user.points.count).to eq(3)
      end

      it 'parses lat/lon correctly' do
        first = user.points.order(:timestamp).first
        expect(first.lat).to be_within(0.0001).of(52.5200)
        expect(first.lon).to be_within(0.0001).of(13.4050)
      end

      it 'parses timestamps' do
        first = user.points.order(:timestamp).first
        expect(first.timestamp).to eq(Time.zone.parse('2024-06-01T10:00:00Z').to_i)
      end
    end

    context 'with extended segments array format' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/polarsteps/segments.json').to_s }

      before { described_class.new(import, user.id, file_path).call }

      it 'creates one point per segment' do
        expect(user.points.count).to eq(2)
      end

      it 'reads lng when lon is missing' do
        first = user.points.order(:timestamp).first
        expect(first.lon).to be_within(0.0001).of(139.8371)
        expect(first.lat).to be_within(0.0001).of(35.6900)
      end

      it 'stores segment id and type in raw_data' do
        first = user.points.order(:timestamp).first
        expect(first.raw_data['segment_id']).to eq('segment-test001-1')
        expect(first.raw_data['type']).to eq('place_visit')
      end
    end

    context 'with malformed entries mixed in' do
      let(:file_path) { Rails.root.join('tmp', "polarsteps_mixed_#{SecureRandom.hex(4)}.json").to_s }

      before do
        File.write(file_path, <<~JSON)
          [
            {"id":"segment-a-1","lat":12.0,"lng":34.0,"time":"2024-01-01T00:00:00Z","arrived":"x","departed":"y"},
            {"id":"segment-a-2","arrived":"x","departed":"y"},
            {"id":"segment-a-3","lat":12.5,"lng":34.5,"time":"not-a-date","arrived":"x","departed":"y"},
            {"id":"segment-a-4","lat":13.0,"lng":35.0,"time":"2024-01-01T01:00:00Z","arrived":"x","departed":"y"}
          ]
        JSON
        described_class.new(import, user.id, file_path).call
      end

      after { File.delete(file_path) if File.exist?(file_path) }

      it 'skips entries missing coordinates or with unparseable timestamps' do
        expect(user.points.count).to eq(2)
      end
    end
  end
end
