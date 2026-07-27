# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReverseGeocoding::Points::FetchData do
  subject(:fetch_data) { described_class.new(point.id).call }

  let(:point) do
    pt = create(:point)
    pt.update_columns(country_id: nil, country_name: nil, city: nil)
    pt.reload
  end

  context 'when Geocoder returns city and country' do
    let!(:germany) do
      Country.find_by(name: 'Germany') || create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
    end

    before do
      allow(Geocoder).to receive(:search).and_return(
        [
          double(
            city: 'Berlin',
            country: 'Germany',
            data: {
              'address' => 'Address',
              'properties' => { 'countrycode' => 'DE' }
            }
          )
        ]
      )
    end

    context 'when point does not have city and country' do
      it 'updates point with city and country' do
        expect { fetch_data }.to change { point.reload.city }
          .from(nil).to('Berlin')
          .and change { point.reload.country_id }.from(nil).to(germany.id)
      end

      it 'finds existing country' do
        fetch_data
        country = point.reload.country
        expect(country.name).to eq('Germany')
        expect(country.iso_a2).to eq('DE')
        expect(country.iso_a3).to eq('DEU')
      end

      it 'updates point with geodata' do
        expect { fetch_data }.to change { point.reload.geodata }.from({}).to(
          'address' => 'Address',
          'properties' => { 'countrycode' => 'DE' }
        )
      end

      it 'calls Geocoder' do
        fetch_data

        expect(Geocoder).to have_received(:search).with([point.lat, point.lon])
      end

      described_class::WRITE_CONTENTION_ERRORS.each do |error_class|
        it "retries when the point update raises #{error_class}" do
          attempts = 0
          allow(Point).to receive(:find).with(point.id).and_return(point)
          allow(point).to receive(:update!).and_wrap_original do |method, *args|
            attempts += 1
            raise error_class, 'write contention' if attempts == 1

            method.call(*args)
          end
          service = described_class.new(point.id)
          allow(service).to receive(:sleep)

          expect { service.call }.to change { point.reload.city }.from(nil).to('Berlin')
          expect(attempts).to eq(2)
        end
      end

      it 'gives up after exhausting the retry budget and reports the failure' do
        allow(ExceptionReporter).to receive(:call)
        allow(Point).to receive(:find).with(point.id).and_return(point)
        allow(point).to receive(:update!).and_raise(ActiveRecord::QueryCanceled, 'write contention')
        service = described_class.new(point.id)
        allow(service).to receive(:sleep)

        service.call

        expect(point).to have_received(:update!).exactly(described_class::WRITE_MAX_RETRIES + 1).times
        expect(ExceptionReporter).to have_received(:call)
      end

      context 'when store_geodata? is disabled' do
        before do
          allow(DawarichSettings).to receive(:store_geodata?).and_return(false)
        end

        it 'does not store geodata' do
          expect { fetch_data }.not_to(change { point.reload.geodata })
        end

        it 'still updates city and country' do
          expect { fetch_data }.to change { point.reload.city }
            .from(nil).to('Berlin')
        end
      end
    end

    context 'when point has city and country' do
      let(:country) { create(:country, name: 'Test Country') }
      let(:point) do
        create(:point, :with_geodata, city: 'Test City', country_id: country.id, reverse_geocoded_at: Time.current)
      end

      before do
        allow(Geocoder).to receive(:search).and_return(
          [double(
            geodata: { 'address' => 'Address' },
            city: 'Berlin',
            country: 'Germany',
            data: {
              'address' => 'Address',
              'properties' => { 'countrycode' => 'DE' }
            }
          )]
        )
      end

      it 'does not update point' do
        expect { fetch_data }.not_to(change { point.reload.city })
      end

      it 'does not call Geocoder' do
        fetch_data

        expect(Geocoder).not_to have_received(:search)
      end
    end
  end

  context 'when Geocoder returns country name that does not exist in database' do
    before do
      allow(Geocoder).to receive(:search).and_return(
        [
          double(
            city: 'Paris',
            country: 'NonExistentCountry',
            data: {
              'address' => 'Address',
              'properties' => { 'city' => 'Paris' }
            }
          )
        ]
      )
    end

    it 'does not set country_id when country is not found' do
      expect { fetch_data }.to change { point.reload.city }
        .from(nil).to('Paris')

      expect(point.reload.country_id).to be_nil
    end
  end

  context 'when point has nil timestamp' do
    let(:point) { create(:point) }

    before do
      # Bypass validations to simulate legacy data with nil timestamp
      point.update_column(:timestamp, nil)
    end

    it 'skips geocoding without raising' do
      expect(Geocoder).not_to receive(:search)

      expect { fetch_data }.not_to raise_error
    end
  end

  context 'when point has nil lonlat' do
    let(:point) { create(:point) }

    before do
      point.update_column(:lonlat, nil)
    end

    it 'skips geocoding without raising' do
      expect(Geocoder).not_to receive(:search)

      expect { fetch_data }.not_to raise_error
    end
  end

  context 'when Geocoder returns an error' do
    before do
      allow(Geocoder).to receive(:search).and_return([double(city: nil, country: nil, data: { 'error' => 'Error' })])
    end

    it 'does not update point' do
      expect { fetch_data }.not_to(change { point.reload.city })
    end
  end

  context 'when the geocoder provider is temporarily unavailable' do
    before do
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)
      allow(Geocoder).to receive(:search).and_raise(Geocoder::LookupTimeout.new('execution expired'))
    end

    it 'does not report a handled provider outage as an application exception' do
      expect { fetch_data }.not_to raise_error
      expect(ExceptionReporter).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(/Reverse geocoding provider error for point #{point.id}/)
    end
  end

  context 'when the geocoder provider returns an invalid response' do
    before do
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)
      allow(Geocoder).to receive(:search).and_raise(Geocoder::ResponseParseError.new('bad gateway'))
    end

    it 'does not report a handled provider response as an application exception' do
      expect { fetch_data }.not_to raise_error
      expect(ExceptionReporter).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(/Reverse geocoding provider error for point #{point.id}/)
    end
  end

  context 'when the geocoder is misconfigured rather than briefly unavailable' do
    [Geocoder::InvalidApiKey, Geocoder::ConfigurationError, Geocoder::OverQueryLimitError].each do |error_class|
      it "still reports #{error_class} so the outage is not silent" do
        allow(ExceptionReporter).to receive(:call)
        allow(Geocoder).to receive(:search).and_raise(error_class.new('misconfigured'))

        expect { fetch_data }.not_to raise_error
        expect(ExceptionReporter).to have_received(:call)
      end
    end
  end

  context 'when the geocoder provider closes the TLS connection unexpectedly' do
    before do
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)
      allow(Geocoder).to receive(:search).and_raise(OpenSSL::SSL::SSLError.new('unexpected eof while reading'))
    end

    it 'does not report a handled provider connection failure as an application exception' do
      expect { fetch_data }.not_to raise_error
      expect(ExceptionReporter).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(/Reverse geocoding provider error for point #{point.id}/)
    end
  end

  context 'when the geocoder TLS failure is not transient' do
    let(:error) { OpenSSL::SSL::SSLError.new('certificate verify failed') }

    before do
      allow(ExceptionReporter).to receive(:call)
      allow(Geocoder).to receive(:search).and_raise(error)
    end

    it 'reports the application exception' do
      expect { fetch_data }.not_to raise_error
      expect(ExceptionReporter).to have_received(:call).with(error)
    end
  end
end
