# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::StartSettingsPointsCountryIdsJob, type: :job do
  describe '#perform' do
    let!(:point_with_country) { create(:point, country_id: 1) }
    let!(:point_without_country1) { create(:point, country_id: nil) }
    let!(:point_without_country2) { create(:point, country_id: nil) }

    it 'enqueues SetPointsCountryIdsJob for points without country_id' do
      expect { described_class.perform_now }.to \
        have_enqueued_job(DataMigrations::SetPointsCountryIdsJob)
          .with(point_without_country1.id)
          .and have_enqueued_job(DataMigrations::SetPointsCountryIdsJob)
          .with(point_without_country2.id)
    end

    it 'does not enqueue jobs for points with country_id' do
      point_with_country.update(country_id: 1)

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
