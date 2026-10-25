# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261022160000_add_track_revisions.rb')
require Rails.root.join('db/migrate/20261023200000_defer_revisions_during_imports.rb')

RSpec.describe AddTrackRevisions, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }
  let(:triggers) do
    connection.select_values(<<~SQL)
      SELECT tgname FROM pg_trigger WHERE tgrelid = 'tracks'::regclass AND tgname LIKE 'tracks_revision_%' ORDER BY tgname
    SQL
  end

  before { migration.down }
  after do
    migration.up
    DeferRevisionsDuringImports.new.up
  end

  it 'creates the revisions table and one trigger per write event' do
    migration.up

    expect(connection.table_exists?(:track_revisions)).to be(true)
    expect(connection.index_name_exists?(:track_revisions, described_class::INDEX_NAME)).to be(true)
    expect(triggers).to eq(
      %w[tracks_revision_delete tracks_revision_insert tracks_revision_truncate tracks_revision_update]
    )
  end

  it 'is idempotent after a complete run' do
    migration.up

    expect { migration.up }.not_to raise_error
    expect(triggers.size).to eq(4)
  end

  it 'completes after a run that stopped before the triggers' do
    connection.create_table(:track_revisions) do |table|
      table.bigint :user_id, null: false
      table.date :month, null: false
      table.uuid :revision, null: false, default: -> { 'gen_random_uuid()' }
    end

    expect { migration.up }.not_to raise_error
    expect(triggers.size).to eq(4)
  end

  it 'gives up instead of queueing behind a transaction that writes to tracks' do
    stub_const("#{described_class}::LOCK_TIMEOUT", '200ms')
    stub_const("#{described_class}::MAX_ATTEMPTS", 1)
    blocker = ActiveRecord::Base.connection_pool.checkout
    blocker.execute('BEGIN')
    blocker.execute('LOCK TABLE tracks IN ROW EXCLUSIVE MODE')
    connection.execute("SET statement_timeout = '5s'")

    expect { migration.up }.to raise_error(ActiveRecord::LockWaitTimeout)
  ensure
    connection.execute('RESET statement_timeout')
    blocker&.execute('ROLLBACK')
    ActiveRecord::Base.connection_pool.checkin(blocker) if blocker
  end
end
