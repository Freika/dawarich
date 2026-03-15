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

    describe 'end_at_after_start_at' do
      it 'rejects end_at equal to start_at' do
        now = Time.current
        ve = build(:video_export, start_at: now, end_at: now)

        expect(ve).not_to be_valid
        expect(ve.errors[:end_at]).to include('must be after start date')
      end

      it 'rejects end_at before start_at' do
        ve = build(:video_export, start_at: Time.current, end_at: 1.hour.ago)

        expect(ve).not_to be_valid
        expect(ve.errors[:end_at]).to include('must be after start date')
      end
    end

    describe 'concurrent_exports_limit' do
      let(:user) { create(:user) }

      it 'rejects a 4th concurrent export' do
        create_list(:video_export, 3, user: user, status: :created)

        ve = build(:video_export, user: user)

        expect(ve).not_to be_valid
        expect(ve.errors[:base]).to include('Too many concurrent video exports (max 3)')
      end

      it 'allows creation when existing exports are completed or failed' do
        create(:video_export, :completed, user: user)
        create(:video_export, :failed, user: user)
        create(:video_export, user: user, status: :created)

        ve = build(:video_export, user: user)

        expect(ve).to be_valid
      end
    end

    describe 'track_belongs_to_user' do
      it 'rejects a track belonging to another user' do
        other_user = create(:user)
        track = create(:track, user: other_user)

        ve = build(:video_export, track: track)

        expect(ve).not_to be_valid
        expect(ve.errors[:track_id]).to include('does not belong to this user')
      end

      it 'accepts a track belonging to the same user' do
        user = create(:user)
        track = create(:track, user: user)

        ve = build(:video_export, user: user, track: track)

        expect(ve).to be_valid
      end
    end

    describe 'config_values_valid' do
      it 'rejects target_duration below 5' do
        ve = build(:video_export, config: { 'target_duration' => 2 })

        expect(ve).not_to be_valid
        expect(ve.errors[:config]).to include('target_duration must be between 5 and 300')
      end

      it 'rejects target_duration above 300' do
        ve = build(:video_export, config: { 'target_duration' => 500 })

        expect(ve).not_to be_valid
        expect(ve.errors[:config]).to include('target_duration must be between 5 and 300')
      end

      it 'rejects invalid orientation' do
        ve = build(:video_export, config: { 'orientation' => 'diagonal' })

        expect(ve).not_to be_valid
        expect(ve.errors[:config]).to include('orientation must be landscape or portrait')
      end

      it 'rejects invalid route_width' do
        ve = build(:video_export, config: { 'route_width' => -1 })

        expect(ve).not_to be_valid
        expect(ve.errors[:config]).to include('route_width must be between 1 and 20')
      end

      it 'rejects route_width above 20' do
        ve = build(:video_export, config: { 'route_width' => 999 })

        expect(ve).not_to be_valid
        expect(ve.errors[:config]).to include('route_width must be between 1 and 20')
      end

      it 'rejects invalid route_color format' do
        ve = build(:video_export, config: { 'route_color' => 'not-a-color' })

        expect(ve).not_to be_valid
        expect(ve.errors[:config]).to include('route_color must be a valid hex color (e.g. #ff0000)')
      end

      it 'accepts valid route_color' do
        ve = build(:video_export, config: { 'route_color' => '#3b82f6' })

        expect(ve).to be_valid
      end
    end
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

    it 'generates a callback_nonce on create' do
      video_export = create(:video_export)

      expect(video_export.callback_nonce).to be_present
      expect(video_export.callback_nonce.length).to be >= 32
    end

    it 'does not overwrite an existing callback_nonce' do
      video_export = create(:video_export)
      original_nonce = video_export.callback_nonce

      video_export.update!(status: :processing)

      expect(video_export.reload.callback_nonce).to eq(original_nonce)
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

  describe '#display_name' do
    it 'returns track_name from config when present' do
      ve = build(:video_export, config: { 'track_name' => 'Morning Run' })

      expect(ve.display_name).to eq('Morning Run')
    end

    it 'returns date range when track_name is absent' do
      ve = build(:video_export,
                 start_at: Time.zone.parse('2026-01-15 10:00'),
                 end_at: Time.zone.parse('2026-01-15 11:00'),
                 config: {})

      expect(ve.display_name).to include('2026-01-15')
    end
  end

  describe '#download_filename' do
    it 'returns parameterized track_name with .mp4 extension' do
      ve = build(:video_export, config: { 'track_name' => 'Morning Run' })

      expect(ve.download_filename).to eq('morning-run.mp4')
    end

    it 'returns date-based filename when track_name is absent' do
      ve = build(:video_export,
                 start_at: Time.zone.parse('2026-01-15 10:00'),
                 config: {})

      expect(ve.download_filename).to eq('route-2026-01-15.mp4')
    end
  end

  describe '#broadcast_status' do
    it 'broadcasts to VideoExportsChannel on status change' do
      ve = create(:video_export, status: :created)

      expect(VideoExportsChannel).to receive(:broadcast_to).with(ve.user, hash_including(:id, :status))

      ve.update!(status: :processing)
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
