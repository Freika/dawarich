# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::ImportParser do
  describe '#call' do
    subject(:service) { described_class.new(import, user.id).call }

    let(:user) do
      create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' })
    end

    let(:immich_data) do
      JSON.parse(File.read(Rails.root.join('spec/fixtures/files/immich/geodata.json')))
    end
    let(:import) { create(:import, user:, raw_data: immich_data) }

    context 'when there are no points' do
      it 'creates new points' do
        expect { service }.to change { Point.count }.by(2)
      end

      it 'creates points with correct attributes' do
        service

        expect(Point.first.latitude.to_f).to eq(59.0000)
        expect(Point.first.longitude.to_f).to eq(30.0000)
        expect(Point.first.timestamp).to eq(978_296_400)
        expect(Point.first.import_id).to eq(import.id)

        expect(Point.second.latitude.to_f).to eq(55.0001)
        expect(Point.second.longitude.to_f).to eq(37.0001)
        expect(Point.second.timestamp).to eq(978_296_400)
        expect(Point.second.import_id).to eq(import.id)
      end
    end

    context 'when there are points with the same coordinates' do
      let!(:existing_point) do
        create(:point, latitude: 59.0000, longitude: 30.0000, timestamp: 978_296_400, user:)
      end

      it 'creates only new points' do
        expect { service }.to change { Point.count }.by(1)
      end
    end
  end
end
