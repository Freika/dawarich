# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261027130300_add_import_scope_to_exports.rb')

RSpec.describe AddImportScopeToExports, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }

  def run_down
    migration.migrate(:down)
    Export.reset_column_information
  end

  after do
    migration.migrate(:up) unless connection.column_exists?(:exports, :import_id)
    Export.reset_column_information
  end

  it 'leaves existing exports without an import scope' do
    export = create(:export)
    run_down

    migration.migrate(:up)
    Export.reset_column_information

    expect(Export.find(export.id).import_id).to be_nil
  end

  it 'finishes when an earlier partial run already added the column' do
    run_down
    connection.add_column :exports, :import_id, :bigint

    expect { migration.migrate(:up) }.not_to raise_error
    expect(connection.column_exists?(:exports, :import_id)).to be(true)
  end
end
