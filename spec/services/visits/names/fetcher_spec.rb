# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Names::Fetcher do
  subject(:fetch_name) { described_class.new([10.0, 10.0]).call }

  context 'when the geocoder provider times out' do
    before do
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)
      allow(Geocoder).to receive(:search).and_raise(Geocoder::LookupTimeout.new('execution expired'))
    end

    it 'returns no name without reporting an application exception' do
      expect(fetch_name).to be_nil
      expect(ExceptionReporter).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(/Geocoding provider error while fetching a visit name/)
    end
  end

  context 'when name building fails unexpectedly' do
    let(:error) { StandardError.new('unexpected failure') }

    before do
      allow(ExceptionReporter).to receive(:call)
      allow(Geocoder).to receive(:search).and_raise(error)
    end

    it 'reports the application exception' do
      expect(fetch_name).to be_nil
      expect(ExceptionReporter).to have_received(:call).with(error)
    end
  end
end
