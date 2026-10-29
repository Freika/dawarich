# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261029120000_add_anomaly_override_to_points.rb')

# DDL is transactional in PostgreSQL, so the example's rollback restores the column.
RSpec.describe AddAnomalyOverrideToPoints do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }

  before do
    ActiveRecord::Migration.verbose = false
    migration.migrate(:down)
    Point.reset_column_information
  end

  after do
    ActiveRecord::Migration.verbose = true
    Point.reset_column_information
  end

  it 'keeps existing points and marks them as not overridden' do
    user = create(:user)
    point = create(:point, user:, anomaly: true)

    migration.migrate(:up)
    Point.reset_column_information

    expect(connection.column_exists?(:points, :anomaly_override, :boolean, null: false, default: false)).to be(true)
    expect(point.reload).to have_attributes(anomaly: true, anomaly_override: false)
  end

  it 'is a no-op when the column already exists' do
    migration.migrate(:up)

    expect { migration.migrate(:up) }.not_to raise_error
    expect(connection.column_exists?(:points, :anomaly_override, :boolean, null: false, default: false)).to be(true)
  end

  it 'rolls back cleanly when the column is already gone' do
    expect { migration.migrate(:down) }.not_to raise_error
    expect(connection.column_exists?(:points, :anomaly_override)).to be(false)
  end
end
