# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhoenixTables do
  let(:connection) { ActiveRecord::Base.connection }

  it 'installs a fresh schema with intact SQL blocks and literals and reuses its storage' do
    user = create(:user)
    digest = create(:users_digest, user: user, year: 2024, month: 3, period_type: :monthly)
    connection.execute('DROP SCHEMA phoenix CASCADE')
    PhoenixSchema.reset!

    Tempfile.create(['phoenix_literals', '.sql']) do |file|
      file.write("DO $body$ BEGIN PERFORM 'escaped'';\nliteral'; PERFORM $$dollar;\nliteral$$; END $body$;\n")
      file.flush
      stub_const('PhoenixTables::SQL_FILES', PhoenixTables::SQL_FILES + [file.path])
      described_class.install!
    end

    expect(described_class.installed?).to be(true)
    expect(connection.select_value("SELECT state FROM phoenix.digest_executions WHERE user_id=#{digest.user_id}"))
      .to eq('generated')
    storage = connection.select_rows('SELECT oid,relfilenode FROM pg_class WHERE relfilenode > 0 ORDER BY oid')
    described_class.install!
    expect(connection.select_rows('SELECT oid,relfilenode FROM pg_class WHERE relfilenode > 0 ORDER BY oid'))
      .to eq(storage)
  end

  it 'repairs a partial schema missing the native digest table and clears its execution rows' do
    connection.execute('DROP TABLE phoenix.digest_executions')
    PhoenixSchema.reset!
    expect(described_class.installed?).to be(false)

    described_class.install!
    expect(described_class.installed?).to be(true)
    connection.execute(<<~SQL)
      INSERT INTO phoenix.digest_executions(effect,user_id,year,month,state)
      VALUES ('digests.calculate_month',1,2024,3,'claimed')
    SQL
    described_class.clear!
    expect(connection.select_value('SELECT count(*) FROM phoenix.digest_executions')).to eq(0)
  end
end
