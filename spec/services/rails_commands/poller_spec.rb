# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe RailsCommands::Poller do
  let(:user) { create(:user) }

  after do
    described_class.stop
    poller_threads.each do |thread|
      thread.kill
      thread.join
    end
    expect(poller_threads).to be_empty
  end

  def sql(text, *binds) = ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([text, *binds]))

  def command!(kind, payload, attempts: 0, available_at: 'now()', leased_until: 'NULL')
    sql(<<~SQL.squish, kind, payload.to_json, attempts).first['id']
      INSERT INTO phoenix.rails_commands (kind, payload, attempts, available_at, leased_until)
      VALUES (?, ?::jsonb, ?, #{available_at}, #{leased_until}) RETURNING id
    SQL
  end

  def commands = sql('SELECT * FROM phoenix.rails_commands ORDER BY id').to_a
  def dead = sql('SELECT * FROM phoenix.rails_commands_dead ORDER BY id').to_a

  def expire_leases! = sql("UPDATE phoenix.rails_commands SET leased_until = now() - interval '1 second' " \
                           'WHERE leased_until IS NOT NULL')

  def make_due! = sql('UPDATE phoenix.rails_commands SET available_at = now()')
  def month_key(user) = Timeline::MonthSummary.cache_key_for(user, Date.new(2026, 6, 1))
  def months(user) = { 'user_id' => user.id, 'started_at' => ['2026-06-15T10:00:00Z'] }
  def stub_bust = allow(Visits::Detection::MachineVisitWipe).to receive(:bust_month_caches)
  def poller_threads = Thread.list.select { _1.name == described_class::THREAD_NAME }

  it 'does nothing before Phoenix ever migrated' do
    expect(described_class.drain_once).to eq(0)

    phoenix_tables!

    connection = ActiveRecord::Base.connection
    expect(connection.select_value("SELECT to_regclass('phoenix.rails_commands')")).not_to be_nil
    expect(connection.select_value("SELECT to_regclass('phoenix.rails_commands_dead')")).not_to be_nil
    expect(described_class.drain_once).to eq(0)
  end

  it 'visit_months_changed busts the named timeline month caches and deletes its row' do
    phoenix_tables!
    Rails.cache.write(month_key(user), 'x')
    command!('visit_months_changed', months(user))

    expect(described_class.drain_once).to eq(1)
    expect(Rails.cache.read(month_key(user))).to be_nil
    expect(commands).to be_empty
    expect(dead).to be_empty
  end

  it 'the claim leases due rows for 60 s and counts the attempt' do
    phoenix_tables!
    id = command!('visit_months_changed', months(user))

    rows = described_class.claim

    expect(rows).to include(a_hash_including('id' => id, 'attempts' => 1, 'lease' => be_present))
    row = commands.first
    expect(row['leased_until']).to be_within(2.seconds).of(60.seconds.from_now)
    expect(row['attempts']).to eq(1)
  end

  it 'a crash after the claim retries the row once the lease expires' do
    phoenix_tables!
    stub_bust
    command!('visit_months_changed', months(user))
    described_class.claim

    expect(described_class.drain_once).to eq(0)
    expect(Visits::Detection::MachineVisitWipe).not_to have_received(:bust_month_caches)

    expire_leases!

    expect(described_class.drain_once).to eq(1)
    expect(Visits::Detection::MachineVisitWipe).to have_received(:bust_month_caches).once
    expect(commands).to be_empty
    expect(dead).to be_empty
  end

  it 'a slow producer does not double-run within its lease, and a late finish deletes nothing' do
    phoenix_tables!
    old = command!('visit_months_changed', months(user)).then { described_class.claim.first }

    expect(described_class.claim).to eq([])

    expire_leases!
    new = described_class.claim.first
    expect(new).to include('id' => old['id'], 'attempts' => 2)
    sql("UPDATE phoenix.rails_commands SET leased_until = now() + interval '2 minutes' WHERE id = #{new['id']}")
    new['lease'] = sql('SELECT leased_until::text AS lease FROM phoenix.rails_commands ' \
                       "WHERE id = #{new['id']}").first['lease']

    allow(Rails.logger).to receive(:warn)
    described_class.complete(old)
    expect(commands).not_to be_empty
    expect(Rails.logger).to have_received(:warn).with(/finished after its lease/)

    described_class.complete(new)
    expect(commands).to be_empty
  end

  it 'success deletes only the leased row' do
    phoenix_tables!
    command!('visit_months_changed', months(user))
    command!('visit_months_changed', months(create(:user)))
    first, second = described_class.claim
    sql("UPDATE phoenix.rails_commands SET leased_until = now() + interval '2 minutes' WHERE id = #{second['id']}")

    described_class.complete(first)
    described_class.complete(second)
    described_class.fail_attempt(second, RuntimeError.new('cache down'))

    expect(commands.map { _1['id'] }).to eq([second['id']])
    expect(commands.first['leased_until']).to be_present
  end

  it 'a raising producer backs off and then succeeds' do
    phoenix_tables!
    stub_bust.and_invoke(->(*) { raise 'cache down' }, ->(*) {})
    id = command!('visit_months_changed', months(user))

    expect(described_class.drain_once).to eq(1)
    row = commands.first
    expect(row).to include('id' => id, 'attempts' => 1, 'leased_until' => nil)
    expect(JSON.parse(row['payload'])).to eq(months(user))
    expect(row['available_at']).to be_within(2.seconds).of(16.seconds.from_now)
    expect(described_class.drain_once).to eq(0)

    make_due!

    expect(described_class.drain_once).to eq(1)
    expect(commands).to be_empty
    expect(dead).to be_empty
    expect(Visits::Detection::MachineVisitWipe).to have_received(:bust_month_caches).twice
  end

  it 'the 25th failing attempt moves the row to dead atomically and logs at error level' do
    phoenix_tables!
    stub_bust.and_raise(RuntimeError, 'cache down')
    id = command!('visit_months_changed', months(user), attempts: 24)
    expect(Rails.logger).to receive(:error).with(/#{id} \(visit_months_changed\) dead after 25 attempts: RuntimeError/)

    expect(described_class.drain_once).to eq(1)
    expect(commands).to be_empty
    expect(dead).to include(a_hash_including('id' => id, 'kind' => 'visit_months_changed', 'attempts' => 25,
                                             'last_error' => 'RuntimeError: cache down'))
    expect(JSON.parse(dead.first['payload'])).to eq(months(user))
  end

  it 'a row whose leases expired 25 times goes to dead without running' do
    phoenix_tables!
    stub_bust
    command!('visit_months_changed', months(user), attempts: 25, leased_until: "now() - interval '1 second'")

    expect(described_class.drain_once).to eq(1)
    expect(Visits::Detection::MachineVisitWipe).not_to have_received(:bust_month_caches)
    expect(dead.first).to include('attempts' => 25, 'last_error' => a_string_starting_with('RailsCommands::Poller::LeaseExpired'))
  end

  it 'a settle statement that fails leaves the row to its lease and loses nothing' do
    phoenix_tables!
    stub_bust
    command!('visit_months_changed', months(user))
    allow(described_class).to receive(:complete).and_raise(ActiveRecord::StatementInvalid, 'db down')
    expect(Rails.logger).to receive(:warn).with(/not settled: ActiveRecord::StatementInvalid/)

    expect(described_class.drain_once).to eq(1)
    expect(commands.first['leased_until']).to be_present

    allow(described_class).to receive(:complete).and_call_original
    expire_leases!

    expect(described_class.drain_once).to eq(1)
    expect(commands).to be_empty
  end

  it 'no row is lost: every claimed row ends deleted, backed off or dead' do
    phoenix_tables!
    users = create_list(:user, 10)
    users.each_with_index do |candidate, index|
      command!('visit_months_changed', months(candidate), attempts: index.zero? ? 24 : 0)
    end
    command!('visit_months_changed', { 'user_id' => 0, 'started_at' => ['2026-06-15T10:00:00Z'] })
    failing = users.first(5)
    stub_bust.and_wrap_original do |method, candidate, times|
      raise 'cache down' if failing.include?(candidate)

      method.call(candidate, times)
    end

    expect(described_class.drain_once).to eq(11)
    expect(dead.size).to eq(1)
    expect(commands.size).to eq(4)
    expect(commands).to all(include('attempts' => 1, 'leased_until' => nil))
    users.last(5).each do |candidate|
      expect(Visits::Detection::MachineVisitWipe).to have_received(:bust_month_caches).with(candidate, kind_of(Array))
    end
    expect(1 + 4 + 5 + 1).to eq(11)
  end

  it 'an unknown kind backs off like a failure' do
    phoenix_tables!
    command!('later_kind', { 'user_id' => user.id })
    expect(Rails.logger).to receive(:warn).with(/failed attempt 1: RailsCommands::Poller::UnknownKind/)

    expect(described_class.drain_once).to eq(1)
    expect(commands.first).to include('attempts' => 1, 'leased_until' => nil)
  end

  it 'the claim skips future and leased rows' do
    phoenix_tables!
    command!('visit_months_changed', months(user), available_at: "now() + interval '1 hour'")
    command!('visit_months_changed', months(create(:user)), leased_until: "now() + interval '1 minute'")

    expect(described_class.drain_once).to eq(0)
  end

  it 'backoff follows attempts⁴ + 15 seconds' do
    expect([1, 2, 24].map { described_class.backoff_seconds(_1) }).to eq([16, 31, 331_791])
  end

  it 'rows run in id order within a claim' do
    phoenix_tables!
    users = create_list(:user, 3)
    users.each { command!('visit_months_changed', months(_1)) }
    stub_bust

    described_class.drain_once

    users.each { expect(Visits::Detection::MachineVisitWipe).to have_received(:bust_month_caches).with(_1, kind_of(Array)).ordered }
  end

  it 'every registered kind declares a repeat guard and a callable' do
    expect(RailsCommands::Registry::HANDLERS.keys).to eq(%w[visit_months_changed airtrail_stats])
    RailsCommands::Registry::HANDLERS.each_value do |handler|
      expect(handler[:guard]).to be_a(String).and be_present
      expect(handler[:call]).to respond_to(:call)
    end
  end

  it 'starts one named poller thread even when started twice' do
    entered = Queue.new
    release = Queue.new
    allow(Rails).to receive(:env).and_return('production'.inquiry)
    allow(described_class).to receive(:drain_safely) do
      entered << Thread.current
      release.pop
    end

    described_class.start
    thread = entered.pop
    described_class.start

    expect(poller_threads).to contain_exactly(thread)
  end

  it 'stops its thread and can start it again' do
    entered = Queue.new
    allow(Rails).to receive(:env).and_return('production'.inquiry)
    allow(described_class).to receive(:drain_safely) do
      entered << Thread.current
      Queue.new.pop
    end

    described_class.start
    first_thread = entered.pop
    described_class.stop

    expect(first_thread).not_to be_alive
    expect(poller_threads).to be_empty

    described_class.start
    second_thread = entered.pop

    expect(second_thread).not_to equal(first_thread)
    expect(poller_threads).to contain_exactly(second_thread)
  end
end
