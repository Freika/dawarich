# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::DropLegacyLatLonJob do
  let(:connection) { ActiveRecord::Base.connection }

  before { allow(ActiveRecord::Base).to receive(:connection).and_return(connection) }

  it 'does nothing when the legacy columns are already gone' do
    allow(connection).to receive(:column_exists?).and_return(false)
    allow(connection).to receive(:execute)

    described_class.perform_now

    expect(connection).not_to have_received(:execute).with(/DROP COLUMN/)
  end

  it 'drops both legacy columns in a single statement' do
    allow(connection).to receive(:column_exists?).and_return(true)
    allow(connection).to receive(:execute)

    described_class.perform_now

    expect(connection).to have_received(:execute).with(
      'ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude'
    )
  end

  it 'resets the lock timeout even when the drop loses the lock race' do
    allow(connection).to receive(:column_exists?).and_return(true)
    allow(connection).to receive(:execute) do |sql|
      raise ActiveRecord::LockWaitTimeout, 'lock timeout' if sql.include?('DROP COLUMN')
    end

    described_class.perform_now

    expect(connection).to have_received(:execute).with('RESET lock_timeout')
  end

  it 'retries rather than failing when the lock is unavailable' do
    allow(connection).to receive(:column_exists?).and_return(true)
    allow(connection).to receive(:execute) do |sql|
      raise ActiveRecord::LockWaitTimeout, 'lock timeout' if sql.include?('DROP COLUMN')
    end

    expect { described_class.perform_now }.to have_enqueued_job(described_class)
  end

  it 'retries when a statement_timeout cancels the drop' do
    allow(connection).to receive(:column_exists?).and_return(true)
    allow(connection).to receive(:execute) do |sql|
      raise ActiveRecord::QueryCanceled, 'statement timeout' if sql.include?('DROP COLUMN')
    end

    expect { described_class.perform_now }.to have_enqueued_job(described_class)
  end
end
