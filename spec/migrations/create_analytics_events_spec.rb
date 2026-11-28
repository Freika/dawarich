# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261124100000_create_analytics_events.rb')

RSpec.describe CreateAnalyticsEvents, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }

  after do
    migration.migrate(:up)
    AnalyticsEvent.reset_column_information
  end

  it 'finishes the dedup index when an earlier run created only the table' do
    connection.remove_index :analytics_events, :dedup_key

    expect { migration.migrate(:up) }.not_to raise_error
    expect(connection.index_exists?(:analytics_events, :dedup_key, unique: true)).to be(true)
  end

  it 'keeps recorded events when replayed' do
    event = AnalyticsEvent.record(user: create(:user), event: :import_succeeded, dedup_key: 'import_succeeded:1')

    migration.migrate(:up)

    expect(AnalyticsEvent.find(event.id).dedup_key).to eq('import_succeeded:1')
  end
end
