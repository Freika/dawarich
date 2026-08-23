# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillPointCountryIdJob, type: :job do
  let(:user) { create(:user) }
  let!(:germany) { create(:country, name: 'Germany') }

  # The country columns are written with update_columns rather than through the
  # factory: the factory's `country` transient creates a Country and assigns
  # the association, and its callbacks also populate country_name, so a row
  # built the obvious way arrives with country_id already set and country_name
  # filled in. Every example below would then pass without the job touching
  # anything. These bypass callbacks so each row is genuinely unresolved.
  def unresolved_point(country_name:, country: nil)
    create(:point, user: user).tap do |point|
      point.update_columns(country_name: country_name, country: country, country_id: nil)
    end
  end

  let!(:named_point) { unresolved_point(country_name: 'Germany') }
  let!(:unknown_point) { unresolved_point(country_name: 'Atlantis') }
  let!(:legacy_point) { unresolved_point(country_name: nil, country: 'Germany') }
  let!(:blank_point) { unresolved_point(country_name: nil) }

  describe '#perform' do
    it 'resolves country_name against countries' do
      described_class.perform_now

      expect(named_point.reload.country_id).to eq(germany.id)
    end

    it 'falls back to the legacy country column' do
      described_class.perform_now

      expect(legacy_point.reload.country_id).to eq(germany.id)
    end

    it 'leaves unmatched and blank rows NULL' do
      described_class.perform_now

      expect(unknown_point.reload.country_id).to be_nil
      expect(blank_point.reload.country_id).to be_nil
    end

    it 'does not overwrite an existing country_id' do
      other = create(:country, name: 'France')
      stamped = create(:point, user: user, country_name: 'Germany')
      stamped.update_column(:country_id, other.id)

      described_class.perform_now

      expect(stamped.reload.country_id).to eq(other.id)
    end

    it 'walks the id range in batches by re-enqueueing itself' do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      first_id = Point.minimum(:id)

      expect { described_class.perform_now(first_id) }.to \
        have_enqueued_job(described_class).with(first_id + 1)
    end

    it 'does not fall through to the legacy column when country_name is set but unmatched' do
      mismatched = unresolved_point(country_name: 'Atlantis', country: 'Germany')

      described_class.perform_now

      expect(mismatched.reload.country_id).to be_nil
    end

    it 'does not re-enqueue past the last point' do
      described_class.perform_now(Point.maximum(:id))

      expect(described_class).not_to have_been_enqueued
    end

    it 'resolves every matchable point across a chained run' do
      stub_const("#{described_class}::BATCH_SIZE", 1)

      perform_enqueued_jobs(only: described_class) { described_class.perform_now }

      expect(named_point.reload.country_id).to eq(germany.id)
      expect(legacy_point.reload.country_id).to eq(germany.id)
      expect(unknown_point.reload.country_id).to be_nil
    end

    it 'halves the batch and retries the same cursor when a batch is aborted' do
      allow_any_instance_of(described_class).to receive(:resolve_countries)
        .and_raise(ActiveRecord::QueryCanceled)
      start_id = Point.minimum(:id)

      expect { described_class.perform_now(start_id) }.to \
        have_enqueued_job(described_class).with(start_id, described_class::BATCH_SIZE / 2)
    end

    it 'hands the smallest batch to the retry machinery instead of shrinking forever' do
      allow_any_instance_of(described_class).to receive(:resolve_countries)
        .and_raise(ActiveRecord::QueryCanceled)
      start_id = Point.minimum(:id)

      expect { described_class.perform_now(start_id, described_class::MIN_BATCH_SIZE) }.to \
        have_enqueued_job(described_class).with(start_id, described_class::MIN_BATCH_SIZE)
    end

    it 'reports batch position so operators can tell running from stalled' do
      allow(Rails.logger).to receive(:info).and_call_original

      described_class.perform_now

      expect(Rails.logger).to have_received(:info).with(/of id range/)
    end

    it 'tells the operator to resume a halved batch at its halved size' do
      allow(Rails.logger).to receive(:error)
      job = described_class.new(42, described_class::MIN_BATCH_SIZE)

      described_class.log_exhaustion(job, ActiveRecord::QueryCanceled.new('canceled'))

      expect(Rails.logger).to have_received(:error)
        .with(/perform_later\(42, #{described_class::MIN_BATCH_SIZE}\)/)
    end
  end
end
