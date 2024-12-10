# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photos::Search do
  let(:user) { create(:user) }
  let(:start_date) { '2024-01-01' }
  let(:end_date) { '2024-03-01' }
  let(:service) { described_class.new(user, start_date: start_date, end_date: end_date) }

  describe '#call' do
    context 'when user has no integrations configured' do
      before do
        allow(user).to receive(:immich_integration_configured?).and_return(false)
        allow(user).to receive(:photoprism_integration_configured?).and_return(false)
      end

      it 'returns an empty array' do
        expect(service.call).to eq([])
      end
    end

    context 'when user has Immich integration configured' do
      let(:immich_photo) { { 'type' => 'image', 'id' => '1' } }
      let(:serialized_photo) { { id: '1', source: 'immich' } }

      before do
        allow(user).to receive(:immich_integration_configured?).and_return(true)
        allow(user).to receive(:photoprism_integration_configured?).and_return(false)

        allow_any_instance_of(Immich::RequestPhotos).to receive(:call)
          .and_return([immich_photo])

        allow_any_instance_of(Api::PhotoSerializer).to receive(:call)
          .and_return(serialized_photo)
      end

      it 'fetches and transforms Immich photos' do
        expect(service.call).to eq([serialized_photo])
      end
    end

    context 'when user has Photoprism integration configured' do
      let(:photoprism_photo) { { 'Type' => 'image', 'id' => '2' } }
      let(:serialized_photo) { { id: '2', source: 'photoprism' } }

      before do
        allow(user).to receive(:immich_integration_configured?).and_return(false)
        allow(user).to receive(:photoprism_integration_configured?).and_return(true)

        allow_any_instance_of(Photoprism::RequestPhotos).to receive(:call)
          .and_return([photoprism_photo])

        allow_any_instance_of(Api::PhotoSerializer).to receive(:call)
          .and_return(serialized_photo)
      end

      it 'fetches and transforms Photoprism photos' do
        expect(service.call).to eq([serialized_photo])
      end
    end

    context 'when user has both integrations configured' do
      let(:immich_photo) { { 'type' => 'image', 'id' => '1' } }
      let(:photoprism_photo) { { 'Type' => 'image', 'id' => '2' } }
      let(:serialized_immich) do
        {
          id: '1',
          latitude: nil,
          longitude: nil,
          localDateTime: nil,
          originalFileName: nil,
          city: nil,
          state: nil,
          country: nil,
          type: 'image',
          source: 'immich',
          orientation: 'landscape'
        }
      end
      let(:serialized_photoprism) do
        {
          id: '2',
          latitude: nil,
          longitude: nil,
          localDateTime: nil,
          originalFileName: nil,
          city: nil,
          state: nil,
          country: nil,
          type: 'image',
          source: 'photoprism',
          orientation: 'landscape'
        }
      end

      before do
        allow(user).to receive(:immich_integration_configured?).and_return(true)
        allow(user).to receive(:photoprism_integration_configured?).and_return(true)

        allow_any_instance_of(Immich::RequestPhotos).to receive(:call)
          .and_return([immich_photo])
        allow_any_instance_of(Photoprism::RequestPhotos).to receive(:call)
          .and_return([photoprism_photo])
      end

      it 'fetches and transforms photos from both services' do
        expect(service.call).to eq([serialized_immich, serialized_photoprism])
      end
    end

    context 'when filtering out videos' do
      let(:immich_photo) { { 'type' => 'video', 'id' => '1' } }

      before do
        allow(user).to receive(:immich_integration_configured?).and_return(true)
        allow(user).to receive(:photoprism_integration_configured?).and_return(false)

        allow_any_instance_of(Immich::RequestPhotos).to receive(:call)
          .and_return([immich_photo])
      end

      it 'excludes video assets' do
        expect(service.call).to eq([])
      end
    end
  end

  describe '#initialize' do
    context 'with default parameters' do
      let(:service_default) { described_class.new(user) }

      it 'sets default start_date' do
        expect(service_default.start_date).to eq('1970-01-01')
      end

      it 'sets default end_date to nil' do
        expect(service_default.end_date).to be_nil
      end
    end

    context 'with custom parameters' do
      it 'sets custom dates' do
        expect(service.start_date).to eq(start_date)
        expect(service.end_date).to eq(end_date)
      end
    end
  end
end
