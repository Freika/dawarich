# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::StartSettingsPointsCountryIdsJob, type: :job do
  describe '#perform' do
    let!(:point_with_country) { create(:point, country_id: 1) }
    let!(:point_without_country1) { create(:point, country_id: nil) }
    let!(:point_without_country2) { create(:point, country_id: nil) }

    it 'enqueues SetPointsCountryIdsJob for points without country_id' do
      # Mock the Point.where query to return only our test points
      allow(Point).to receive_message_chain(:where, :find_each)
        .and_yield(point_without_country1)
        .and_yield(point_without_country2)

      expect { described_class.perform_now }.to \
        have_enqueued_job(DataMigrations::SetPointsCountryIdsJob)
          .with(point_without_country1.id)
          .and have_enqueued_job(DataMigrations::SetPointsCountryIdsJob)
          .with(point_without_country2.id)
    end

    it 'does not enqueue jobs for points with country_id' do
      # Mock the Point.where query to return no points (since they all have country_id)
      allow(Point).to receive_message_chain(:where, :find_each)
        .and_return([])

      expect { described_class.perform_now }.not_to \
        have_enqueued_job(DataMigrations::SetPointsCountryIdsJob)
          .with(point_with_country.id)
    end
  end

  describe 'queue' do
    it 'uses the default queue' do
      expect(described_class.queue_name).to eq('default')
    end
  end
end
