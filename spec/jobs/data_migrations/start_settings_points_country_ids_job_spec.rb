# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::StartSettingsPointsCountryIdsJob, type: :job do
  describe '#perform' do
    let!(:point_with_country) do
      create(:point).tap { |p| p.update_columns(country_id: 1) }
    end
    let!(:point_without_country1) do
      create(:point).tap { |p| p.update_columns(country_id: nil) }
    end
    let!(:point_without_country2) do
      create(:point).tap { |p| p.update_columns(country_id: nil) }
    end

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

    it 'selects only point IDs while enqueueing' do
      queries = []
      callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        described_class.perform_now
      end

      point_queries = queries.select { |sql| sql.include?('FROM "points"') }
      expect(point_queries).not_to be_empty
      expect(point_queries).to all(include('"points"."id"'))
      expect(point_queries).to all(satisfy { |sql| !sql.include?('"points"."accuracy"') })
      expect(point_queries).to all(satisfy { |sql| !sql.include?('"points"."lonlat"') })
    end
  end

  describe 'queue' do
    it 'uses the data_migrations queue' do
      expect(described_class.queue_name).to eq('data_migrations')
    end
  end
end
