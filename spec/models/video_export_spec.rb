# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoExport do
  subject(:video_export) { build(:video_export) }

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:track).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:start_at) }
    it { is_expected.to validate_presence_of(:end_at) }
  end

  describe 'enums' do
    it {
      expect(video_export).to define_enum_for(:status)
        .with_values(created: 0, processing: 1, completed: 2, failed: 3)
    }
  end

  describe 'ActiveStorage' do
    it 'has one attached file' do
      expect(described_class.new.file).to be_an_instance_of(ActiveStorage::Attached::One)
    end
  end

  describe 'callbacks' do
    it 'sets processing_started_at when status changes to processing' do
      video_export = create(:video_export, status: :created)

      expect { video_export.update!(status: :processing) }
        .to change { video_export.reload.processing_started_at }.from(nil)
    end

    it 'enqueues VideoExportJob on create' do
      expect { create(:video_export) }.to have_enqueued_job(VideoExportJob)
    end

    it 'purges attached file on destroy' do
      video_export = create(:video_export)
      video_export.file.attach(
        io: StringIO.new('fake video'),
        filename: 'test.mp4',
        content_type: 'video/mp4'
      )

      expect { video_export.destroy }.to change(ActiveStorage::Attachment, :count).by(-1)
    end
  end

  describe '#config' do
    it 'defaults to empty hash' do
      expect(described_class.new.config).to eq({})
    end

    it 'stores configuration options' do
      config = {
        'orientation' => 'landscape',
        'speed_multiplier' => 10,
        'map_style' => 'dark',
        'map_behavior' => 'north_up',
        'overlays' => { 'time' => true, 'speed' => true, 'distance' => false, 'track_name' => true }
      }
      video_export = create(:video_export, config: config)

      expect(video_export.reload.config).to eq(config)
    end
  end

  describe 'status transitions' do
    it 'can transition from created to processing' do
      video_export = create(:video_export, status: :created)
      video_export.update!(status: :processing)

      expect(video_export).to be_processing
    end

    it 'can transition from processing to completed' do
      video_export = create(:video_export, status: :processing)
      video_export.update!(status: :completed)

      expect(video_export).to be_completed
    end

    it 'can transition from processing to failed' do
      video_export = create(:video_export, status: :processing)
      video_export.update!(status: :failed, error_message: 'Render timeout')

      expect(video_export).to be_failed
      expect(video_export.error_message).to eq('Render timeout')
    end
  end
end
