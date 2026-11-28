# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260816150000_create_point_dimension_tables.rb')

RSpec.describe CreatePointDimensionTables do
  subject(:migration) { described_class.new }

  before do
    allow(migration).to receive(:sleep)
    allow(migration).to receive(:execute).and_call_original
    allow(migration).to receive(:execute).with(/ADD COLUMN IF NOT EXISTS source_id/)
                                         .and_raise(ActiveRecord::LockWaitTimeout, 'lock timeout')
  end

  # Recording the migration without the column left instances short of it for
  # good (#3972); a failed boot is retried, a recorded migration never is.
  it 'fails instead of recording itself when the column never lands' do
    expect { migration.up }.to raise_error(ActiveRecord::LockWaitTimeout)
  end
end
