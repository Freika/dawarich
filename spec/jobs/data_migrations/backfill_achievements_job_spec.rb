# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillAchievementsJob do
  let(:backfill) { [Achievements::BulkCheckJob, { notify: false, force: true, stale_only: true }] }

  def stub_region_loading
    allow(Achievements::Registry).to receive(:subdivision_codes).and_return(Set['DE-BY'])
    allow(Achievements::LoadRegions).to receive(:new)
      .and_return(instance_double(Achievements::LoadRegions, call: true))
  end

  after { Flipper.disable(:achievements) }

  context 'on Cloud' do
    before do
      create(:country)
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    it 'schedules a silent stale-only check before the feature is switched on' do
      stub_region_loading
      Flipper.disable(:achievements)

      expect { described_class.perform_now }.to have_enqueued_job(backfill[0]).with(**backfill[1])
    end

    it 'loads missing region boundaries first' do
      described_class.perform_now

      expect(Region.where(code: Achievements::Registry.subdivision_codes).count)
        .to eq(Achievements::Registry.subdivision_codes.size)
    end
  end

  context 'on a self-hosted instance' do
    before do
      create(:country)
      stub_region_loading
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    end

    it 'does nothing while the feature is off' do
      Flipper.disable(:achievements)

      expect { described_class.perform_now }.not_to have_enqueued_job(Achievements::BulkCheckJob)
    end

    it 'schedules the backfill once the feature is on' do
      Flipper.enable(:achievements)

      expect { described_class.perform_now }.to have_enqueued_job(backfill[0]).with(**backfill[1])
    end
  end

  it 'waits for countries to be seeded' do
    stub_region_loading
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect { described_class.perform_now }.not_to have_enqueued_job(Achievements::BulkCheckJob)
  end
end
