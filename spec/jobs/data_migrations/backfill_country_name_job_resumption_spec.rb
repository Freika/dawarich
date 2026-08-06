# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillCountryNameJob do
  describe 'resumption' do
    let(:user) { create(:user) }
    let!(:points) do
      Array.new(6) do
        create(:point, user: user).tap do |point|
          point.update_columns(country: 'Germany', country_name: nil)
        end
      end
    end

    def country_names
      Point.where(id: points.map(&:id)).order(:id).pluck(:country_name)
    end

    it 'stops partway through when the worker is shutting down' do
      described_class.perform_later(batch_size: 2)

      interrupt_job_during_step(described_class, :backfill, cursor: points[3].id) do
        perform_enqueued_jobs
      end

      expect(country_names).to eq(['Germany', 'Germany', 'Germany', 'Germany', nil, nil])
    end

    it 'finishes the remaining points when it resumes' do
      described_class.perform_later(batch_size: 2)

      interrupt_job_during_step(described_class, :backfill, cursor: points[3].id) do
        perform_enqueued_jobs
      end
      perform_enqueued_jobs

      expect(country_names).to all(eq('Germany'))
    end

    it 'completes in a single run when the worker is not shutting down' do
      perform_enqueued_jobs { described_class.perform_later(batch_size: 2) }

      expect(country_names).to all(eq('Germany'))
      expect(enqueued_jobs).to be_empty
    end
  end
end
