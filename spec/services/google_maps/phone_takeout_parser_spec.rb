# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::PhoneTakeoutParser do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }

    context 'when file content is an object' do
      # This file contains 3 duplicates
      let(:file_path) { Rails.root.join('spec/fixtures/files/google/phone-takeout.json') }
      let(:raw_data) { JSON.parse(File.read(file_path)) }
      let(:import) { create(:import, user:, name: 'phone_takeout.json', raw_data:) }

      context 'when file exists' do
        it 'creates points' do
          expect { parser }.to change { Point.count }.by(4)
        end
      end
    end

    context 'when file content is an array' do
      # This file contains 4 duplicates
      let(:file_path) { Rails.root.join('spec/fixtures/files/google/location-history.json') }
      let(:raw_data) { JSON.parse(File.read(file_path)) }
      let(:import) { create(:import, user:, name: 'phone_takeout.json', raw_data:) }

      context 'when file exists' do
        it 'creates points' do
          expect { parser }.to change { Point.count }.by(8)
        end

        it 'creates points with correct data' do
          parser

          expect(Point.all[6].lat).to eq('27.696576')
          expect(Point.all[6].lon).to eq('-97.376949')
          expect(Point.all[6].timestamp).to eq(1_693_180_140)

          expect(Point.last.lat).to eq('27.709617')
          expect(Point.last.lon).to eq('-97.375988')
          expect(Point.last.timestamp).to eq(1_693_180_320)
        end
      end
    end
  end
end
