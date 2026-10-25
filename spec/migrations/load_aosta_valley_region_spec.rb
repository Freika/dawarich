# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261025120000_load_aosta_valley_region.rb')

RSpec.describe LoadAostaValleyRegion do
  subject(:migration) { described_class.new }

  it 'loads Aosta Valley' do
    create(:country)

    migration.up

    expect(Region.where(code: 'IT-23')).to exist
  end

  it 'skips loading on a fresh install without countries' do
    expect { migration.up }.not_to change(Region, :count)
  end

  it 'rebuilds every user silently, whatever calculation version their progress carries' do
    expect { migration.up }.to have_enqueued_job(Achievements::BulkCheckJob).with(notify: false, rebuild: true)
  end
end
