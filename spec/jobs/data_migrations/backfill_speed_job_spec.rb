# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillSpeedJob do
  describe '#perform' do
    let(:user) { create(:user) }

    # Helper: create a point then null out speed via update_column
    # to simulate old points created before the before_save callback existed.
    def create_legacy_point(**attrs)
      point = create(:point, user: user, **attrs)
      point.update_column(:speed, nil) unless attrs.key?(:speed) && attrs[:speed].present?
      point
    end

    context 'with numeric velocity' do
      let!(:point) { create_legacy_point(velocity: '12.5') }

      it 'backfills speed from velocity' do
        expect(point.reload.speed).to be_nil

        described_class.new.perform

        expect(point.reload.speed).to eq(12.5)
      end
    end

    context 'with integer velocity' do
      let!(:point) { create_legacy_point(velocity: '25') }

      it 'backfills speed as float' do
        described_class.new.perform

        expect(point.reload.speed).to eq(25.0)
      end
    end

    context 'with zero velocity' do
      let!(:point) { create_legacy_point(velocity: '0') }

      it 'backfills speed as zero' do
        described_class.new.perform

        expect(point.reload.speed).to eq(0.0)
      end
    end

    context 'with nil velocity' do
      let!(:point) { create_legacy_point(velocity: nil) }

      it 'leaves speed as nil' do
        described_class.new.perform

        expect(point.reload.speed).to be_nil
      end
    end

    context 'with non-numeric velocity' do
      let!(:point) do
        p = create(:point, user: user, velocity: '0')
        p.update_columns(velocity: 'invalid', speed: nil)
        p
      end

      it 'skips the point' do
        described_class.new.perform

        expect(point.reload.speed).to be_nil
      end
    end

    context 'with speed already set' do
      let!(:point) { create(:point, user: user, velocity: '12.5', speed: 99.0) }

      before { point.update_column(:speed, 99.0) }

      it 'does not overwrite existing speed' do
        described_class.new.perform

        expect(point.reload.speed).to eq(99.0)
      end
    end

    context 'with negative velocity' do
      let!(:point) do
        p = create(:point, user: user, velocity: '0')
        p.update_columns(velocity: '-3.5', speed: nil)
        p
      end

      it 'backfills negative speed' do
        described_class.new.perform

        expect(point.reload.speed).to eq(-3.5)
      end
    end

    context 'with multiple points in batches' do
      let!(:points) do
        3.times.map do |i|
          p = create_legacy_point(velocity: (i * 10.5).to_s, timestamp: 1.day.ago.to_i + i)
          p
        end
      end

      it 'processes all points across batches' do
        described_class.new.perform(batch_size: 2)

        points.each(&:reload)
        expect(points.map(&:speed)).to eq([0.0, 10.5, 21.0])
      end
    end

    it 'enqueues from migration with delay' do
      expect {
        DataMigrations::BackfillSpeedJob.set(wait: 3.minutes).perform_later
      }.to have_enqueued_job(described_class)
    end
  end
end
