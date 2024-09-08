# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::ImportGeodata do
  describe '#call' do
    subject(:service) { described_class.new(user).call }

    let(:user) do
      create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' })
    end
    let(:immich_data) do
      [
        {
          "exifInfo": {
            "dateTimeOriginal": '2022-12-31T23:17:06.170Z',
            "latitude": 52.0000,
            "longitude": 13.0000
          }
        },
        {
          "exifInfo": {
            "dateTimeOriginal": '2022-12-31T23:21:53.140Z',
            "latitude": 52.0000,
            "longitude": 13.0000
          }
        }
      ].to_json
    end

    context 'when user has immich_url and immich_api_key' do
      before do
        stub_request(
          :any,
          %r{http://immich\.app/api/timeline/bucket\?size=MONTH&timeBucket=(19[7-9][0-9]|20[0-9]{2})-(0?[1-9]|1[0-2])-(0?[1-9]|[12][0-9]|3[01])}
        ).to_return(status: 200, body: immich_data, headers: {})
      end

      it 'creates import' do
        expect { service }.to change { Import.count }.by(1)
      end

      it 'enqueues ImportJob' do
        expect(ImportJob).to receive(:perform_later)

        service
      end

      context 'when import already exists' do
        before { service }

        it 'does not create new import' do
          expect { service }.not_to(change { Import.count })
        end

        it 'does not enqueue ImportJob' do
          expect(ImportJob).to_not receive(:perform_later)

          service
        end
      end
    end

    context 'when user has no immich_url' do
      before do
        user.settings['immich_url'] = nil
        user.save
      end

      it 'raises ArgumentError' do
        expect { service }.to raise_error(ArgumentError, 'Immich URL is missing')
      end
    end

    context 'when user has no immich_api_key' do
      before do
        user.settings['immich_api_key'] = nil
        user.save
      end

      it 'raises ArgumentError' do
        expect { service }.to raise_error(ArgumentError, 'Immich API key is missing')
      end
    end
  end
end
