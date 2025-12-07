# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::Archiver do
  let(:user) { create(:user) }
  let(:archiver) { described_class.new }

  before do
    allow(PointsChannel).to receive(:broadcast_to)
  end

  describe '#call' do
    context 'when archival is disabled' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('false')
      end

      it 'returns early without processing' do
        result = archiver.call

        expect(result).to eq({ processed: 0, archived: 0, failed: 0 })
      end
    end

    context 'when archival is enabled' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
      end

      let!(:old_points) do
        # Create points 3 months ago (definitely older than 2 month lag)
        old_date = 3.months.ago.beginning_of_month
        create_list(:point, 5, user: user,
                              timestamp: old_date.to_i,
                              raw_data: { lon: 13.4, lat: 52.5 })
      end

      it 'archives old points' do
        expect { archiver.call }.to change(Points::RawDataArchive, :count).by(1)
      end

      it 'marks points as archived' do
        archiver.call

        expect(Point.where(raw_data_archived: true).count).to eq(5)
      end

      it 'nullifies raw_data column' do
        archiver.call
        Point.where(user: user).find_each do |point|
          expect(point.raw_data).to eq({})
        end
      end

      it 'returns correct stats' do
        result = archiver.call

        expect(result[:processed]).to eq(1)
        expect(result[:archived]).to eq(5)
        expect(result[:failed]).to eq(0)
      end
    end

    context 'with points from multiple months' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
      end

      let!(:june_points) do
        june_date = 4.months.ago.beginning_of_month
        create_list(:point, 3, user: user,
                              timestamp: june_date.to_i,
                              raw_data: { lon: 13.4, lat: 52.5 })
      end

      let!(:july_points) do
        july_date = 3.months.ago.beginning_of_month
        create_list(:point, 2, user: user,
                              timestamp: july_date.to_i,
                              raw_data: { lon: 14.0, lat: 53.0 })
      end

      it 'creates separate archives for each month' do
        expect { archiver.call }.to change(Points::RawDataArchive, :count).by(2)
      end

      it 'archives all points' do
        archiver.call
        expect(Point.where(raw_data_archived: true).count).to eq(5)
      end
    end
  end

  describe '#archive_specific_month' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
    end

    let(:test_date) { 3.months.ago.beginning_of_month.utc }
    let!(:june_points) do
      create_list(:point, 3, user: user,
                            timestamp: test_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    it 'archives specific month' do
      expect do
        archiver.archive_specific_month(user.id, test_date.year, test_date.month)
      end.to change(Points::RawDataArchive, :count).by(1)
    end

    it 'creates archive with correct metadata' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      archive = user.raw_data_archives.last

      expect(archive.user_id).to eq(user.id)
      expect(archive.year).to eq(test_date.year)
      expect(archive.month).to eq(test_date.month)
      expect(archive.point_count).to eq(3)
      expect(archive.chunk_number).to eq(1)
    end

    it 'attaches compressed file' do
      archiver.archive_specific_month(user.id, test_date.year, test_date.month)

      archive = user.raw_data_archives.last
      expect(archive.file).to be_attached
      expect(archive.file.key).to match(%r{raw_data_archives/\d+/\d{4}/\d{2}/001\.jsonl\.gz})
    end
  end

  describe 'append-only architecture' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
    end

    # Use UTC from the start to avoid timezone issues
    let(:test_date_utc) { 3.months.ago.utc.beginning_of_month }
    let!(:june_points_batch1) do
      create_list(:point, 2, user: user,
                            timestamp: test_date_utc.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    it 'creates additional chunks for same month' do
      # First archival
      archiver.archive_specific_month(user.id, test_date_utc.year, test_date_utc.month)
      expect(Points::RawDataArchive.for_month(user.id, test_date_utc.year, test_date_utc.month).count).to eq(1)
      expect(Points::RawDataArchive.last.chunk_number).to eq(1)

      # Verify first batch is archived
      june_points_batch1.each(&:reload)
      expect(june_points_batch1.all?(&:raw_data_archived)).to be true

      # Add more points for same month (retrospective import)
      # Use unique timestamps to avoid uniqueness validation errors
      mid_month = test_date_utc + 15.days
      june_points_batch2 = [
        create(:point, user: user, timestamp: mid_month.to_i, raw_data: { lon: 14.0, lat: 53.0 }),
        create(:point, user: user, timestamp: (mid_month + 1.hour).to_i, raw_data: { lon: 14.0, lat: 53.0 })
      ]

      # Verify second batch exists and is not archived
      expect(june_points_batch2.all? { |p| !p.raw_data_archived }).to be true

      # Second archival should create chunk 2
      archiver.archive_specific_month(user.id, test_date_utc.year, test_date_utc.month)
      expect(Points::RawDataArchive.for_month(user.id, test_date_utc.year, test_date_utc.month).count).to eq(2)
      expect(Points::RawDataArchive.last.chunk_number).to eq(2)
    end
  end

  describe 'advisory locking' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')
    end

    let!(:june_points) do
      old_date = 3.months.ago.beginning_of_month
      create_list(:point, 2, user: user,
                            timestamp: old_date.to_i,
                            raw_data: { lon: 13.4, lat: 52.5 })
    end

    it 'prevents duplicate processing with advisory locks' do
      # Simulate lock couldn't be acquired (returns nil/false)
      allow(ActiveRecord::Base).to receive(:with_advisory_lock).and_return(false)

      result = archiver.call
      expect(result[:processed]).to eq(0)
      expect(result[:failed]).to eq(0)
    end
  end
end
