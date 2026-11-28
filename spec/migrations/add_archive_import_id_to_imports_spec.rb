# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261124100100_add_archive_import_id_to_imports.rb')

RSpec.describe AddArchiveImportIdToImports, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }

  def run_down
    migration.migrate(:down)
    Import.reset_column_information
  end

  after do
    migration.migrate(:up)
    Import.reset_column_information
  end

  it 'leaves existing imports without an archive link' do
    import = create(:import)
    run_down

    migration.migrate(:up)
    Import.reset_column_information

    expect(Import.find(import.id).archive_import_id).to be_nil
  end

  it 'finishes when an earlier partial run already added the column' do
    run_down
    connection.add_column :imports, :archive_import_id, :bigint

    expect { migration.migrate(:up) }.not_to raise_error
    expect(connection.index_exists?(:imports, :archive_import_id)).to be(true)
  end
end
