# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261029170000_add_track_to_flights.rb')

RSpec.describe AddTrackToFlights, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }

  before do
    migration.migrate(:down)
    Flight.reset_column_information
  end

  after do
    migration.migrate(:up)
    Flight.reset_column_information
  end

  it 'adds empty track columns and keeps existing flights' do
    flight = create(:flight, flight_number: 'AF1235')

    migration.migrate(:up)
    Flight.reset_column_information

    flight = Flight.find(flight.id)
    expect(flight.flight_number).to eq('AF1235')
    expect(flight.track_coordinates).to be_nil
    expect(flight.track_updated_at).to be_nil
  end

  it 'finishes when an earlier partial run already added one of the columns' do
    connection.add_column :flights, :track_coordinates, :jsonb

    expect { migration.migrate(:up) }.not_to raise_error
    expect(connection.column_exists?(:flights, :track_coordinates, :jsonb)).to be(true)
    expect(connection.column_exists?(:flights, :track_updated_at, :datetime)).to be(true)
  end
end
