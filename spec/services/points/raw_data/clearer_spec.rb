# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::Clearer do
  let(:user) { create(:user) }
  let(:clearer) { described_class.new }

  before do
    allow(PointsChannel).to receive(:broadcast_to)
  end

  describe '#clear_specific_archive' do
    let(:test_date) { 3.months.ago.beginning_of_month.utc }
    let!(:points) do
      create_list(:point, 5, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    let(:archive) do
      # Create and verify archive
      archiver = Points::RawData::Archiver.new
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      archive = Points::RawDataArchive.last
      verifier = Points::RawData::Verifier.new
      verifier.verify_specific_archive(archive.id)

      archive.reload
    end

    it 'clears raw_data for verified archive' do
      expect(Point.where(user: user).pluck(:raw_data)).to all(eq({ 'lon' => 13.4, 'lat' => 52.5 }))

      clearer.clear_specific_archive(archive.id)

      expect(Point.where(user: user).pluck(:raw_data)).to all(eq({}))
    end

    it 'does not clear unverified archive' do
      # Create unverified archive
      archiver = Points::RawData::Archiver.new
      mid_month = test_date + 15.days
      create_list(:point, 3, user: user,
                            timestamp: mid_month.to_i,
                            raw_data: { lon: 14.0, lat: 53.0 })
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      unverified_archive = Points::RawDataArchive.where(verified_at: nil).last

      result = clearer.clear_specific_archive(unverified_archive.id)

      expect(result[:cleared]).to eq(0)
    end

    it 'is idempotent (safe to run multiple times)' do
      clearer.clear_specific_archive(archive.id)
      first_result = Point.where(user: user).pluck(:raw_data)

      clearer.clear_specific_archive(archive.id)
      second_result = Point.where(user: user).pluck(:raw_data)

      expect(first_result).to eq(second_result)
      expect(first_result).to all(eq({}))
    end
  end

  describe '#clear_month' do
    let(:test_date) { 3.months.ago.beginning_of_month.utc }

    before do
      # Create points and archive
      create_list(:point, 5, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })

      archiver = Points::RawData::Archiver.new
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      # Verify archive
      verifier = Points::RawData::Verifier.new
      verifier.verify_month(user.id, test_date.year, test_date.month)
    end

    it 'clears all verified archives for a month' do
      expect(Point.where(user: user, raw_data: {}).count).to eq(0)

      clearer.clear_month(user.id, test_date.year, test_date.month)

      expect(Point.where(user: user, raw_data: {}).count).to eq(5)
    end
  end

  describe '#call' do
    let(:test_date) { 3.months.ago.beginning_of_month.utc }

    before do
      # Create points and archive
      create_list(:point, 5, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })

      archiver = Points::RawData::Archiver.new
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      # Verify archive
      verifier = Points::RawData::Verifier.new
      verifier.verify_month(user.id, test_date.year, test_date.month)
    end

    it 'clears all verified archives' do
      expect(Point.where(raw_data: {}).count).to eq(0)

      result = clearer.call

      expect(result[:cleared]).to eq(5)
      expect(Point.where(raw_data: {}).count).to eq(5)
    end

    it 'skips unverified archives' do
      # Create another month without verifying
      new_date = 4.months.ago.beginning_of_month.utc
      create_list(:point, 3, user: user,
                            timestamp: new_date.to_i,
                            raw_data: { lon: 14.0, lat: 53.0 })

      archiver = Points::RawData::Archiver.new
      archiver.archive_specific_month(user.id, new_date.year, new_date.month)

      result = clearer.call

      # Should only clear the verified month (5 points)
      expect(result[:cleared]).to eq(5)

      # Unverified month should still have raw_data
      unverified_points = Point.where(user: user)
                               .where('timestamp >= ? AND timestamp < ?',
                                      new_date.to_i,
                                      (new_date + 1.month).to_i)
      expect(unverified_points.pluck(:raw_data)).to all(eq({ 'lon' => 14.0, 'lat' => 53.0 }))
    end

    it 'is idempotent (safe to run multiple times)' do
      first_result = clearer.call

      # Use a new instance for second call
      new_clearer = Points::RawData::Clearer.new
      second_result = new_clearer.call

      expect(first_result[:cleared]).to eq(5)
      expect(second_result[:cleared]).to eq(0) # Already cleared
    end

    it 'handles large batches' do
      # Stub batch size to test batching logic
      stub_const('Points::RawData::Clearer::BATCH_SIZE', 2)

      result = clearer.call

      expect(result[:cleared]).to eq(5)
      expect(Point.where(raw_data: {}).count).to eq(5)
    end

    it 'does not clear points whose raw_data_archived was set to false' do
      # Pick one of the 5 archived+verified points and simulate a restore:
      # set raw_data_archived to false and give it new raw_data directly in DB.
      restored_point = Point.where(user: user, raw_data_archived: true).first
      restored_point.update_columns(raw_data_archived: false, raw_data: { 'restored' => true })

      clearer.call

      restored_point.reload
      expect(restored_point.raw_data).to eq({ 'restored' => true })

      # The other 4 points should have been cleared
      other_points = Point.where(user: user).where.not(id: restored_point.id)
      expect(other_points.pluck(:raw_data)).to all(eq({}))
    end
  end
end
