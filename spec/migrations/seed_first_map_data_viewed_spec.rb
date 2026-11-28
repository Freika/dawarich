# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261125100000_seed_first_map_data_viewed.rb')

RSpec.describe SeedFirstMapDataViewed do
  let(:migration) { described_class.new }
  let(:importer) { create(:user) }
  let(:demo_only) { create(:user) }
  let(:fresh) { create(:user) }
  let(:failed_only) { create(:user) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    create(:import, user: importer, status: :completed, points_count: 10)
    create(:import, user: importer, demo: true, status: :completed, points_count: 10)
    create(:import, user: demo_only, demo: true, status: :completed, points_count: 10)
    create(:import, user: failed_only, status: :failed, points_count: 0)
    fresh
  end

  def seeded_user_ids
    AnalyticsEvent.event_first_map_data_viewed.pluck(:user_id)
  end

  it 'marks users who already have their own imports as having seen their map' do
    migration.migrate(:up)

    expect(seeded_user_ids).to contain_exactly(importer.id)
    expect(Analytics::FirstMapView.pending?(importer)).to be(false)
  end

  it 'keeps the event pending for users with only demo data, failed imports or no imports' do
    migration.migrate(:up)
    create(:import, user: demo_only)
    create(:import, user: fresh)

    expect(Analytics::FirstMapView.pending?(demo_only)).to be(true)
    expect(Analytics::FirstMapView.pending?(fresh)).to be(true)
    expect(Analytics::FirstMapView.pending?(failed_only)).to be(true)
  end

  it 'leaves an already recorded event alone when replayed' do
    recorded = AnalyticsEvent.record(user: importer, event: :first_map_data_viewed,
                                     dedup_key: Analytics::FirstMapView.dedup_key(importer))

    2.times { migration.migrate(:up) }

    expect(seeded_user_ids).to eq([importer.id])
    expect(AnalyticsEvent.find(recorded.id).properties).to eq({})
  end

  it 'removes only the seeded rows on rollback' do
    other = create(:user)
    real = AnalyticsEvent.record(user: other, event: :first_map_data_viewed,
                                 dedup_key: Analytics::FirstMapView.dedup_key(other))
    migration.migrate(:up)

    migration.migrate(:down)

    expect(AnalyticsEvent.pluck(:id)).to eq([real.id])
  end

  it 'seeds nothing on a self-hosted instance' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    migration.migrate(:up)

    expect(seeded_user_ids).to be_empty
  end
end
