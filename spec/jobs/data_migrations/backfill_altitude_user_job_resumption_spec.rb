# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillAltitudeUserJob do
  describe 'resumption' do
    let(:user) { create(:user) }
    let!(:points) do
      Array.new(6) do |index|
        create(:point, user: user, altitude: 100 + index,
                       raw_data: { 'alt' => 200 + index, 'lat' => 52.225, 'lon' => 13.332 })
      end
    end

    def altitudes
      Point.where(id: points.map(&:id)).order(:id).pluck(:altitude).map(&:to_i)
    end

    def interrupt_after_fourth_point(&block)
      interrupt_job_during_step(described_class, :backfill_from_raw_data, cursor: points[3].id, &block)
    end

    it 'stops partway through when the worker is shutting down' do
      described_class.perform_later(user.id, batch_size: 2)

      interrupt_after_fourth_point { perform_enqueued_jobs }

      expect(altitudes).to eq([200, 201, 202, 203, 104, 105])
    end

    it 'finishes the remaining points when it resumes' do
      described_class.perform_later(user.id, batch_size: 2)

      interrupt_after_fourth_point { perform_enqueued_jobs }
      perform_enqueued_jobs

      expect(altitudes).to eq([200, 201, 202, 203, 204, 205])
    end

    it 'resumes from the cursor rather than rewalking the table' do
      described_class.perform_later(user.id, batch_size: 2)

      interrupt_after_fourth_point { perform_enqueued_jobs }

      scanned = []
      allow(Points::AltitudeExtractor).to receive(:from_raw_data).and_wrap_original do |original, raw_data|
        scanned << raw_data['alt']
        original.call(raw_data)
      end
      perform_enqueued_jobs

      expect(scanned).to eq([204, 205])
    end

    it 'survives being interrupted more than once' do
      described_class.perform_later(user.id, batch_size: 2)

      interrupt_job_during_step(described_class, :backfill_from_raw_data, cursor: points[1].id) do
        perform_enqueued_jobs
      end
      expect(altitudes).to eq([200, 201, 102, 103, 104, 105])

      interrupt_job_during_step(described_class, :backfill_from_raw_data, cursor: points[3].id) do
        perform_enqueued_jobs
      end
      expect(altitudes).to eq([200, 201, 202, 203, 104, 105])

      perform_enqueued_jobs

      expect(altitudes).to eq([200, 201, 202, 203, 204, 205])
    end

    it 'completes in a single run when the worker is not shutting down' do
      perform_enqueued_jobs { described_class.perform_later(user.id, batch_size: 2) }

      expect(altitudes).to eq([200, 201, 202, 203, 204, 205])
      expect(enqueued_jobs).to be_empty
    end
  end
end
