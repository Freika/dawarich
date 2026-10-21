# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhoenixSchema do
  def catalog_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 if payload[:name] == 'PhoenixSchema' }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end

  before { described_class.reset! }

  it 'asks the catalog once per process for a present table and every time for a missing one' do
    present = catalog_queries { 2.times { expect(described_class.table?('once_claims')).to be(true) } }
    missing = catalog_queries { 2.times { expect(described_class.table?('no_such_table')).to be(false) } }

    expect(present).to eq(1)
    expect(missing).to eq(2)
  end

  it 'asks again in a forked process and after a reset' do
    described_class.table?('leases')
    allow(Process).to receive(:pid).and_return(Process.pid + 1)

    expect(catalog_queries { described_class.table?('leases') }).to eq(1)
    described_class.reset!
    expect(catalog_queries { described_class.table?('leases') }).to eq(1)
  end
end
