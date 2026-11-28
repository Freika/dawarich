# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261023200000_defer_revisions_during_imports.rb')

RSpec.describe DeferRevisionsDuringImports, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }
  let(:guarded_functions) do
    connection.select_values(<<~SQL)
      SELECT proname FROM pg_proc
      WHERE proname ~ '^(points|tracks)_revision_(insert|update|delete|truncate)$'
        AND prosrc LIKE '%dawarich.defer_revisions%'
      ORDER BY proname
    SQL
  end

  after { migration.up }

  it 'lets every point and track revision trigger skip deferred imports' do
    migration.down
    migration.up

    expect(guarded_functions.size).to eq(8)
  end

  it 'restores the unconditional triggers on rollback' do
    migration.down

    expect(guarded_functions).to be_empty
  end
end
