# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhoenixRegistrationSetting do
  let(:connection) { ActiveRecord::Base.connection }
  let(:key) { 'dawarich/registration_enabled' }

  around do |example|
    with_legacy_registration do
      example.run
    ensure
      connection.execute('DROP TABLE IF EXISTS phoenix.registration_setting')
      PhoenixSchema.reset!
      Rails.cache.delete(key)
    end
  end

  it 'migrated registration reads and writes true false nil without cache access' do
    phoenix_registration!
    connection.execute('INSERT INTO phoenix.registration_setting (enabled) VALUES (true)')
    expect(Rails.cache).not_to receive(:fetch)
    expect(Rails.cache).not_to receive(:write)

    [false, nil, true].each do |value|
      expect(described_class.put(value)).to be(true)
      expect(described_class.fetch(false)).to eq(value)
      expect(connection.select_rows('SELECT enabled FROM phoenix.registration_setting')).to eq([[value]])
    end
  end

  it 'unmigrated registration retains Rails cache fetch and write' do
    expect(PhoenixSchema.table?('registration_setting')).to be(false)
    Rails.cache.write(key, false)
    expect(described_class.fetch(true)).to be(false)
    Rails.cache.delete(key)
    expect(described_class.fetch(true)).to be(true)
    expect(Rails.cache.read(key)).to be(true)
    [false, nil, true].each do |value|
      expect(described_class.put(value)).to be(true)
      expect(described_class.fetch(true)).to eq(value)
      expect(Rails.cache.read(key)).to eq(value)
    end
  end

  it 'present table with missing row or SQL error never enables legacy fallback' do
    phoenix_registration!
    expect(Rails.cache).not_to receive(:fetch)
    expect(Rails.cache).not_to receive(:write)
    expect { described_class.fetch(true) }.to raise_error(described_class::IncompleteUpgrade)
    expect { described_class.put(true) }.to raise_error(described_class::IncompleteUpgrade)
    expect(connection.select_rows('SELECT enabled FROM phoenix.registration_setting')).to be_empty
    connection.execute('INSERT INTO phoenix.registration_setting (enabled) VALUES (false)')
    connection.execute('ALTER TABLE phoenix.registration_setting RENAME COLUMN enabled TO unavailable')
    expect do
      connection.transaction(requires_new: true) { described_class.fetch(true) }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect do
      connection.transaction(requires_new: true) { described_class.put(true) }
    end.to raise_error(ActiveRecord::StatementInvalid)
  end
end
