# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'achievements:backfill' do
  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?('achievements:backfill')
    Rake::Task['achievements:backfill'].reenable
  end

  it 'is wired after database setup in every supported release path' do
    root = Rails.root

    expect(root.join('Procfile').read).to match(/db:migrate.*achievements:backfill/)
    expect(root.join('app.json').read).to match(/db:migrate.*achievements:backfill/)
    expect(root.join('docker/web-entrypoint.sh').read).to match(/db:seed.*achievements:backfill/m)
  end

  it 'loads missing boundaries and schedules a silent stale-only backfill' do
    create(:country)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(Achievements::Registry).to receive(:subdivision_codes).and_return(Set['DE-BY'])
    allow(Achievements::LoadRegions).to receive(:new).and_return(instance_double(Achievements::LoadRegions, call: true))

    expect { Rake::Task['achievements:backfill'].invoke }
      .to have_enqueued_job(Achievements::BulkCheckJob).with(notify: false, force: true, stale_only: true)
  end

  context 'on a self-hosted instance' do
    before do
      create(:country)
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(Achievements::Registry).to receive(:subdivision_codes).and_return(Set['DE-BY'])
      allow(Achievements::LoadRegions).to receive(:new)
        .and_return(instance_double(Achievements::LoadRegions, call: true))
    end

    after { Flipper.disable(:achievements) }

    it 'skips the backfill while the feature is off' do
      Flipper.disable(:achievements)

      expect { Rake::Task['achievements:backfill'].invoke }.not_to have_enqueued_job(Achievements::BulkCheckJob)
    end

    it 'schedules the backfill once the feature is on' do
      Flipper.enable(:achievements)

      expect { Rake::Task['achievements:backfill'].invoke }
        .to have_enqueued_job(Achievements::BulkCheckJob).with(notify: false, force: true, stale_only: true)
    end
  end
end
