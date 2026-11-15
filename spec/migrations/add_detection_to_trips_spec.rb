# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261110090200_add_detection_to_trips.rb')

RSpec.describe AddDetectionToTrips do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  around { |example| ActiveRecord::Migration.suppress_messages { example.run } }

  after { [Trip, TripDetectionDismissal].each(&:reset_column_information) }

  it 'finishes when an earlier run already added the columns and the table' do
    expect { migration.migrate(:up) }.not_to raise_error
    expect { migration.migrate(:down) }.not_to raise_error
    expect { migration.migrate(:down) }.not_to raise_error
    expect(connection.column_exists?(:trips, :origin)).to be(false)

    migration.migrate(:up)

    expect(connection.column_exists?(:trips, :origin, :integer, null: false, default: '0')).to be(true)
    expect(connection.table_exists?(:trip_detection_dismissals)).to be(true)
  end

  it 'marks existing trips as created by the user and untouched' do
    trip = create(:trip)
    migration.migrate(:down)
    migration.migrate(:up)
    Trip.reset_column_information

    expect(Trip.find(trip.id)).to have_attributes(origin: 'manual', user_edited_at: nil)
  end
end
