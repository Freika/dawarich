# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261027130200_add_unavailable_import_scope_to_exports.rb')

RSpec.describe AddUnavailableImportScopeToExports, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }

  def run_down
    migration.migrate(:down)
    Export.reset_column_information
  end

  after do
    migration.migrate(:up) unless connection.column_exists?(:exports, :import_scope_unavailable)
    Export.reset_column_information
  end

  it 'keeps existing exports unscoped by marking their import scope as available' do
    export = create(:export)
    run_down

    migration.migrate(:up)
    Export.reset_column_information

    expect(Export.find(export.id).import_scope_unavailable).to be(false)
  end

  it 'finishes when an earlier partial run already added the column' do
    run_down
    connection.add_column :exports, :import_scope_unavailable, :boolean, default: false, null: false

    expect { migration.migrate(:up) }.not_to raise_error
    expect(connection.column_exists?(:exports, :import_scope_unavailable, :boolean)).to be(true)
  end
end
