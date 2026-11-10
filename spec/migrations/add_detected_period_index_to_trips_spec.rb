# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261110090300_add_detected_period_index_to_trips.rb')

RSpec.describe AddDetectedPeriodIndexToTrips, :non_transactional do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  around { |example| ActiveRecord::Migration.suppress_messages { example.run } }

  after { migration.migrate(:up) }

  it 'finishes when an earlier run already created the index' do
    expect { migration.migrate(:up) }.not_to raise_error
    expect { migration.migrate(:down) }.not_to raise_error
    expect { migration.migrate(:down) }.not_to raise_error
    expect(connection.index_name_exists?(:trips, 'index_trips_on_detected_period')).to be(false)
  end

  it 'rebuilds an index an aborted concurrent run left invalid' do
    connection.execute(<<~SQL.squish)
      UPDATE pg_index SET indisvalid = FALSE
      WHERE indexrelid = 'index_trips_on_detected_period'::regclass
    SQL

    migration.migrate(:up)

    valid = connection.select_value(<<~SQL.squish)
      SELECT indisvalid FROM pg_index WHERE indexrelid = 'index_trips_on_detected_period'::regclass
    SQL
    expect(valid).to be(true)
  end

  it 'makes the index unique only for untouched detected trips' do
    migration.migrate(:down)
    migration.migrate(:up)

    index = connection.indexes(:trips).find { |i| i.name == 'index_trips_on_detected_period' }
    expect(index).to have_attributes(unique: true, columns: %w[user_id started_at ended_at])
    expect(index.where).to include('origin = 1').and include('user_edited_at IS NULL')
  end
end
