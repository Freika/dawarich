# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261116120000_add_period_to_places.rb')

RSpec.describe AddPeriodToPlaces do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  around do |example|
    ActiveRecord::Migration.suppress_messages { example.run }
  end

  after do
    connection.execute('ALTER TABLE places ADD COLUMN IF NOT EXISTS started_on date')
    connection.execute('ALTER TABLE places ADD COLUMN IF NOT EXISTS ended_on date')
    Place.reset_column_information
  end

  def roll_back
    migration.migrate(:down)
    Place.reset_column_information
  end

  def apply
    migration.migrate(:up)
    Place.reset_column_information
  end

  it 'adds both dates again after a rollback' do
    roll_back
    expect(Place.column_names).not_to include('started_on', 'ended_on')

    apply

    expect(Place.columns_hash.values_at('started_on', 'ended_on').map { |column| [column.type, column.null] })
      .to eq([[:date, true], [:date, true]])
  end

  it 'completes after a run that stopped after the first column' do
    roll_back
    connection.execute('ALTER TABLE places ADD COLUMN started_on date')

    expect { apply }.not_to raise_error

    expect(Place.column_names).to include('started_on', 'ended_on')
  end

  it 'can be applied twice and rolled back twice, as a replayed deploy does' do
    expect { 2.times { apply } }.not_to raise_error
    expect { 2.times { roll_back } }.not_to raise_error
    expect(Place.column_names).not_to include('started_on', 'ended_on')
  end

  it 'keeps existing places, leaving their period empty' do
    place = create(:place, name: 'Office', visit_radius: 120)
    roll_back

    apply

    expect(Place.find(place.id)).to have_attributes(name: 'Office', visit_radius: 120, started_on: nil, ended_on: nil)
  end

  it 'drops only its own columns on the way down' do
    place = create(:place, name: 'Office', started_on: Date.new(2019, 9, 1))

    roll_back

    expect(Place.find(place.id).name).to eq('Office')
  end
end
