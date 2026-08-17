# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillPointCountryIdJob, type: :job do
  let(:user) { create(:user) }
  let!(:germany) { create(:country, name: 'Germany') }

  let!(:named_point) do
    create(:point, user: user, country_name: 'Germany', country_id: nil)
  end
  let!(:unknown_point) do
    create(:point, user: user, country_name: 'Atlantis', country_id: nil)
  end
  let!(:legacy_point) do
    create(:point, user: user, country_name: nil, country: 'Germany', country_id: nil)
  end
  let!(:blank_point) do
    create(:point, user: user, country_name: nil, country: nil, country_id: nil)
  end

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
  end
end
