# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::PhoneTakeoutImporter do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }

    before do
      import.file.attach(io: File.open(file_path), filename: 'phone_takeout.json', content_type: 'application/json')
    end

    context 'when file content is an object' do
      # This file contains 3 duplicates
      let(:file_path) { Rails.root.join('spec/fixtures/files/google/phone-takeout_w_3_duplicates.json') }
      let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/json') }
      let(:import) { create(:import, user:, name: 'phone_takeout.json', file:) }

      context 'when file exists' do
        it 'creates points' do
          expect { parser }.to change { Point.count }.by(4)
        end
      end
    end

    context 'when file content is an array' do
      # This file contains 4 duplicates
      let(:file_path) { Rails.root.join('spec/fixtures/files/google/location-history.json') }
      let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/json') }
      let(:import) { create(:import, user:, name: 'phone_takeout.json', file:) }

      context 'when file exists' do
        it 'creates points' do
          expect { parser }.to change { Point.count }.by(8)
        end

        it 'creates points with correct data' do
          parser

          expect(user.points[6].lat).to eq(27.696576)
          expect(user.points[6].lon).to eq(-97.376949)
          expect(user.points[6].timestamp).to eq(1_693_180_140)

          expect(user.points.last.lat).to eq(27.709617)
          expect(user.points.last.lon).to eq(-97.375988)
          expect(user.points.last.timestamp).to eq(1_693_180_320)
        end
      end
    end
  end
end
