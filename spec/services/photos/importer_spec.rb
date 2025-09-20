# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photos::Importer do
  describe '#call' do
    subject(:service) { described_class.new(import, user.id).call }

    let(:user) do
      create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' })
    end

    let(:immich_data) do
      JSON.parse(File.read(Rails.root.join('spec/fixtures/files/immich/geodata.json')))
    end
    let(:import) { create(:import, user:) }

    let(:file_path) { Rails.root.join('spec/fixtures/files/immich/geodata.json') }
    let(:file) { Rack::Test::UploadedFile.new(file_path, 'text/plain') }

    before do
      import.file.attach(io: File.open(file_path), filename: 'immich_geodata.json', content_type: 'application/json')
    end

    context 'when there are no points' do
      it 'creates new points' do
        expect { service }.to change { Point.count }.by(2)
      end

      it 'creates points with correct attributes' do
        service

        first_point = user.points.first
        second_point = user.points.second

        expect(first_point.lat.to_f).to eq(59.0000)
        expect(first_point.lon.to_f).to eq(30.0000)
        expect(first_point.timestamp).to eq(978_296_400)
        expect(first_point.import_id).to eq(import.id)

        expect(second_point.lat.to_f).to eq(55.0001)
        expect(second_point.lon.to_f).to eq(37.0001)
        expect(second_point.timestamp).to eq(978_296_400)
        expect(second_point.import_id).to eq(import.id)
      end
    end

    context 'when there are points with the same coordinates' do
      let!(:existing_point) do
        create(:point, lonlat: 'POINT(30.0000 59.0000)', timestamp: 978_296_400, user:)
      end

      it 'creates only new points' do
        expect { service }.to change { Point.count }.by(1)
      end
    end
  end
end
