# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::GooglePhotosGeodataJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }

    it 'calls GooglePhotos::ImportGeodata service' do
      import_service = instance_double(GooglePhotos::ImportGeodata, call: true)
      allow(GooglePhotos::ImportGeodata).to receive(:new).with(user).and_return(import_service)

      described_class.new.perform(user.id)

      expect(GooglePhotos::ImportGeodata).to have_received(:new).with(user)
      expect(import_service).to have_received(:call)
    end

    it 'is enqueued in the imports queue' do
      expect(described_class.new.queue_name).to eq('imports')
    end
  end
end
