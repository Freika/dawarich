# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::FogHexagons do
  subject(:result) { described_class.new(user:, start_date:, end_date:).call }

  let(:user) { create(:user) }
  let(:start_date) { Time.zone.parse('2024-05-01T00:00:00Z') }
  let(:end_date) { Time.zone.parse('2024-06-30T23:59:59Z') }

  def ts(string)
    Time.zone.parse(string).to_i
  end

  context 'with stats in range' do
    before do
      create(:stat, user:, year: 2024, month: 5, h3_hex_ids: [
               ['8828308281fffff', 3, ts('2024-05-10T10:00:00Z'), ts('2024-05-10T12:00:00Z')],
               ['8828308283fffff', 1, ts('2024-05-11T10:00:00Z'), ts('2024-05-11T10:05:00Z')]
             ])
      create(:stat, user:, year: 2024, month: 6, h3_hex_ids: [
               ['8828308281fffff', 2, ts('2024-06-01T09:00:00Z'), ts('2024-06-01T09:30:00Z')]
             ])
    end

    it 'returns the union of cell ids across months, deduplicated' do
      expect(result['h3_indexes']).to contain_exactly('8828308281fffff', '8828308283fffff')
    end

    it 'reports the count in metadata' do
      expect(result['metadata']['count']).to eq(2)
    end
  end

  context 'with stats outside the requested months' do
    before do
      create(:stat, user:, year: 2024, month: 4, h3_hex_ids: [
               ['8828308285fffff', 5, ts('2024-04-15T10:00:00Z'), ts('2024-04-15T11:00:00Z')]
             ])
    end

    it 'excludes them' do
      expect(result['h3_indexes']).to be_empty
    end
  end

  context 'with a partial-month range' do
    let(:start_date) { Time.zone.parse('2024-05-20T00:00:00Z') }
    let(:end_date) { Time.zone.parse('2024-05-31T23:59:59Z') }

    before do
      create(:stat, user:, year: 2024, month: 5, h3_hex_ids: [
               ['8828308281fffff', 3, ts('2024-05-10T10:00:00Z'), ts('2024-05-12T12:00:00Z')],
               ['8828308283fffff', 2, ts('2024-05-25T10:00:00Z'), ts('2024-05-25T11:00:00Z')]
             ])
    end

    it 'excludes cells whose visit window does not overlap the range' do
      expect(result['h3_indexes']).to contain_exactly('8828308283fffff')
    end
  end

  context 'with malformed rows' do
    before do
      create(:stat, user:, year: 2024, month: 5, h3_hex_ids: [
               [nil, 1, ts('2024-05-10T10:00:00Z'), ts('2024-05-10T11:00:00Z')],
               [],
               ['8828308283fffff', 1, nil, nil]
             ])
    end

    it 'skips blank ids and tolerates missing timestamps' do
      expect(result['h3_indexes']).to contain_exactly('8828308283fffff')
    end
  end

  context 'with legacy hash-shaped h3_hex_ids' do
    before do
      create(:stat, user:, year: 2024, month: 5, h3_hex_ids: { 'area_too_large' => true })
      create(:stat, user:, year: 2024, month: 6, h3_hex_ids: [
               ['8828308281fffff', 1, ts('2024-06-01T09:00:00Z'), ts('2024-06-01T09:30:00Z')]
             ])
    end

    it 'ignores hash entries and keeps valid rows' do
      expect(result['h3_indexes']).to contain_exactly('8828308281fffff')
    end
  end

  context 'with no stats' do
    it 'returns an empty collection' do
      expect(result['h3_indexes']).to eq([])
      expect(result['metadata']['count']).to eq(0)
    end
  end

  context 'with a stat that has nil h3_hex_ids' do
    before { create(:stat, user:, year: 2024, month: 5, h3_hex_ids: nil) }

    it 'returns an empty collection' do
      expect(result['h3_indexes']).to eq([])
    end
  end

  context 'with a range spanning a year boundary' do
    let(:start_date) { Time.zone.parse('2023-12-01T00:00:00Z') }
    let(:end_date) { Time.zone.parse('2024-01-31T23:59:59Z') }

    before do
      create(:stat, user:, year: 2023, month: 12, h3_hex_ids: [
               ['8828308281fffff', 1, ts('2023-12-15T10:00:00Z'), ts('2023-12-15T11:00:00Z')]
             ])
      create(:stat, user:, year: 2024, month: 1, h3_hex_ids: [
               ['8828308283fffff', 1, ts('2024-01-15T10:00:00Z'), ts('2024-01-15T11:00:00Z')]
             ])
    end

    it 'includes both months' do
      expect(result['h3_indexes']).to contain_exactly('8828308281fffff', '8828308283fffff')
    end
  end
end
