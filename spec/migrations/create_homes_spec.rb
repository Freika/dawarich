# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261110090000_create_homes.rb')

RSpec.describe CreateHomes do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  around { |example| ActiveRecord::Migration.suppress_messages { example.run } }

  it 'finishes when an earlier run already created the table' do
    expect { migration.migrate(:up) }.not_to raise_error
    expect { migration.migrate(:down) }.not_to raise_error
    expect { migration.migrate(:down) }.not_to raise_error
    expect(connection.table_exists?(:homes)).to be(false)

    migration.migrate(:up)

    expect(connection.check_constraints(:homes).map(&:name)).to include('homes_end_not_before_start')
  end

  it 'starts the re-created table empty and refuses an end before the start' do
    create(:home)
    migration.migrate(:down)
    migration.migrate(:up)
    Home.reset_column_information

    expect(Home.count).to eq(0)
    home = build(:home, started_on: Date.new(2026, 5, 1), ended_on: Date.new(2026, 4, 1))
    expect { home.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /homes_end_not_before_start/)
  end
end
