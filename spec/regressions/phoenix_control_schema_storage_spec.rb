# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix control schema storage' do
  it 'installs control tables before example transactions and reuses their storage' do
    pool = ActiveRecord::Base.connection_pool
    other = pool.checkout
    begin
      expect(other.select_value("SELECT to_regclass('phoenix.job_owners') IS NOT NULL")).to be(true)
      expect(other.select_value("SELECT to_regclass('phoenix.import_blob_purges') IS NOT NULL")).to be(true)
      connection = ActiveRecord::Base.connection
      before = connection.select_rows('SELECT oid,relfilenode FROM pg_class WHERE relfilenode > 0 ORDER BY oid')
      2.times { phoenix_tables! }
      expect(connection.select_rows('SELECT oid,relfilenode FROM pg_class WHERE relfilenode > 0 ORDER BY oid'))
        .to eq(before)
    ensure
      pool.checkin(other)
    end
  end
end
