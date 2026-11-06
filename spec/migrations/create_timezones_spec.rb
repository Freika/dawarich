# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261029150000_create_timezones.rb')

RSpec.describe CreateTimezones do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }
  let(:kansas) { 'SRID=4326;POLYGON((-100 37, -94.6 37, -94.6 40, -100 40, -100 37))' }

  around { |example| ActiveRecord::Migration.suppress_messages { example.run } }

  it 'rolls back and re-creates the table with its spatial index' do
    migration.migrate(:down)
    expect(connection.table_exists?(:timezones)).to be(false)

    migration.migrate(:up)

    expect(connection.table_exists?(:timezones)).to be(true)
    expect(connection.index_exists?(:timezones, :geom, using: :gist)).to be(true)
  end

  it 'starts the re-created table empty and ready for boundaries' do
    Timezone.create!(tzid: 'America/Chicago', geom: kansas)
    migration.migrate(:down)
    migration.migrate(:up)
    Timezone.reset_column_information

    expect(Timezone.count).to eq(0)
    Timezone.create!(tzid: 'America/Chicago', geom: kansas)
    expect(Timezones::Lookup.call(wichita: [-97.34, 37.69])).to eq(wichita: 'America/Chicago')
  end
end
