# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Export, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(created: 0, processing: 1, completed: 2, failed: 3) }
    it { is_expected.to define_enum_for(:file_format).with_values(json: 0, gpx: 1, archive: 2) }
    it { is_expected.to define_enum_for(:file_type).with_values(points: 0, user_data: 1) }
  end

  describe 'points command producer' do
    let(:user) { create(:user) }

    before do
      user
      JobOutbox.delete_all
      clear_enqueued_jobs
    end

    def export_jobs
      enqueued_jobs.select { |job| job[:job] == ExportJob }
    end

    it 'points export with command:exports.points owned by oban writes one outbox row in the create transaction; ' \
       'rollback leaves neither' do
      job_owner!('command:exports.points', :oban)

      ActiveRecord::Base.transaction do
        export = create(:export, user:, file_type: :points)
        expect(JobOutbox.where(command_type: 'exports.points', aggregate_id: export.id).count).to eq(1)
        raise ActiveRecord::Rollback
      end
      expect([described_class.count, JobOutbox.count]).to eq([0, 0])

      export = create(:export, user:, file_type: :points)
      expect(JobOutbox.sole).to have_attributes(command_type: 'exports.points', aggregate_id: export.id,
                                                dedupe_key: "points-export:#{export.id}",
                                                payload: { 'export_id' => export.id, 'user_id' => user.id })
    end

    it 'sidekiq owner enqueues ExportJob only after commit' do
      job_owner!('command:exports.points', :sidekiq)

      export = ActiveRecord::Base.transaction do
        create(:export, user:, file_type: :points).tap { expect(export_jobs).to be_empty }
      end

      expect(export_jobs.map { |job| job[:args] }).to eq([[export.id]])
    end

    it 'user_data, archive and non-created exports produce nothing' do
      %i[sidekiq oban].each do |owner|
        job_owner!('command:exports.points', owner)
        create(:export, user:, file_type: :user_data)
        create(:export, user:, file_type: :points, file_format: :archive)
        create(:export, user:, file_type: :points, status: :processing)
      end

      expect(JobOutbox.count).to eq(0)
      expect(export_jobs).to be_empty
    end
  end

  describe 'callbacks' do
    describe 'after_commit' do
      context 'when the export is created' do
        let(:export) { build(:export, file_type: :points) }

        it 'enqueues the ExportJob' do
          expect { export.save! }.to have_enqueued_job(ExportJob)
        end

        context 'when the export is a user data export' do
          let(:export) { build(:export, file_type: :user_data) }

          it 'does not enqueue the ExportJob' do
            expect { export.save! }.not_to have_enqueued_job(ExportJob).with(export.id)
          end
        end
      end

      context 'when the export is destroyed' do
        let(:export) { create(:export) }

        it 'removes the attached file when present' do
          allow(export.file).to receive(:attached?).and_return(true)
          expect(export.file).to receive(:purge_later)

          export.destroy!
        end

        it 'does not error when file is not attached' do
          allow(export.file).to receive(:attached?).and_return(false)

          expect { export.destroy! }.not_to raise_error
        end

        it 'does not error when legacy url file is missing from disk' do
          export.update_column(:url, 'exports/missing_file.json')

          expect { export.destroy! }.not_to raise_error
        end
      end
    end
  end
end
