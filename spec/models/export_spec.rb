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

  describe 'callbacks' do
    describe 'after_commit' do
      context 'when the export is created' do
        let(:export) { build(:export, file_type: :points) }

        it 'enqueues the ExportJob' do
          expect(ExportJob).to receive(:perform_later)

          export.save!
        end

        context 'when the export is a user data export' do
          let(:export) { build(:export, file_type: :user_data) }

          it 'does not enqueue the ExportJob' do
            expect(ExportJob).not_to receive(:perform_later).with(export.id)

            export.save!
          end
        end
      end

      context 'when the export is destroyed' do
        let(:export) { create(:export) }

        it 'removes the attached file' do
          expect(export.file).to receive(:purge_later)

          export.destroy!
        end
      end
    end
  end
end
