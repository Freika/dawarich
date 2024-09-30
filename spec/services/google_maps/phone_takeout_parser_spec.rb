# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::PhoneTakeoutParser do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }

    context 'when file content is an object' do
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
      let(:file_path) { Rails.root.join('spec/fixtures/files/google/location-history.json') }
      let(:raw_data) { JSON.parse(File.read(file_path)) }
      let(:import) { create(:import, user:, name: 'phone_takeout.json', raw_data:) }

      context 'when file exists' do
        it 'creates points' do
          expect { parser }.to change { Point.count }.by(8)
        end

        it 'creates points with correct data' do
          parser

          expect(Point.all[6].latitude).to eq(27.696576.to_d)
          expect(Point.all[6].longitude).to eq(-97.376949.to_d)
          expect(Point.all[6].timestamp).to eq(1_693_180_140)

          expect(Point.last.latitude).to eq(27.709617.to_d)
          expect(Point.last.longitude).to eq(-97.375988.to_d)
          expect(Point.last.timestamp).to eq(1_693_180_320)
        end
      end
    end
  end
end
