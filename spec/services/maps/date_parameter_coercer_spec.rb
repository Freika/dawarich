# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::DateParameterCoercer do
  describe '.call' do
    subject(:coerce_date) { described_class.call(param) }

    context 'with integer parameter' do
      let(:param) { 1_717_200_000 }

      it 'returns the integer unchanged' do
        expect(coerce_date).to eq(1_717_200_000)
      end
    end

    context 'with numeric string parameter' do
      let(:param) { '1717200000' }

      it 'converts to integer' do
        expect(coerce_date).to eq(1_717_200_000)
      end
    end

    context 'with ISO date string parameter' do
      let(:param) { '2024-06-01T00:00:00Z' }

      it 'parses and converts to timestamp' do
        expected_timestamp = Time.parse('2024-06-01T00:00:00Z').to_i
        expect(coerce_date).to eq(expected_timestamp)
      end
    end

    context 'with date string parameter' do
      let(:param) { '2024-06-01' }

      it 'parses and converts to timestamp' do
        expected_timestamp = Time.parse('2024-06-01').to_i
        expect(coerce_date).to eq(expected_timestamp)
      end
    end

    context 'with invalid date string' do
      let(:param) { 'invalid-date' }

      it 'raises InvalidDateFormatError' do
        expect { coerce_date }.to raise_error(
          Maps::DateParameterCoercer::InvalidDateFormatError,
          'Invalid date format: invalid-date'
        )
      end
    end

    context 'with nil parameter' do
      let(:param) { nil }

      it 'converts to 0' do
        expect(coerce_date).to eq(0)
      end
    end

    context 'with float parameter' do
      let(:param) { 1_717_200_000.5 }

      it 'converts to integer' do
        expect(coerce_date).to eq(1_717_200_000)
      end
    end
  end
end