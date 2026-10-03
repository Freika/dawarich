# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::CheckJob do
  let(:user) { create(:user) }

  before do
    clear_achievement_checks(user.id)
  end

  def with_current_progress
    version = Achievements::RegionSetChecker::CALCULATION_VERSION
    create(:achievement_progress, user: user, achievement_key: Achievements::Progress::EXPLORATION_KEY,
                                  state: { 'calculation_version' => version })
  end

  it 'runs the checker for the user' do
    checker = instance_double(Achievements::RegionSetChecker, call: nil)
    allow(Achievements::RegionSetChecker).to receive(:new)
      .with(user, notify: false, oldest_timestamp: nil).and_return(checker)

    described_class.perform_now(user.id, notify: false)

    expect(checker).to have_received(:call)
  end

  it 'forwards the oldest timestamp to the checker' do
    with_current_progress
    checker = instance_double(Achievements::RegionSetChecker, call: nil)
    allow(Achievements::RegionSetChecker).to receive(:new)
      .with(user, notify: true, oldest_timestamp: 123).and_return(checker)

    described_class.perform_now(user.id, oldest_timestamp: 123)

    expect(checker).to have_received(:call)
  end

  it 'keeps a user first computation silent' do
    checker = instance_double(Achievements::RegionSetChecker, call: nil)
    allow(Achievements::RegionSetChecker).to receive(:new)
      .with(user, notify: false, oldest_timestamp: nil).and_return(checker)

    described_class.perform_now(user.id)

    expect(checker).to have_received(:call)
  end

  it 'does nothing for a missing user' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  describe 'when Oban owns achievement checks' do
    before { job_owner!('command:achievements.check', :oban) }

    it 'forwards one achievements.check command with the merged oldest timestamp when Oban owns the key' do
      described_class.defer(user.id, oldest_timestamp: 50)

      expect(Achievements::RegionSetChecker).not_to receive(:new)
      described_class.perform_now(user.id, notify: true, oldest_timestamp: 70)

      expect(JobOutbox.pending.sole).to have_attributes(
        command_type: 'achievements.check', dedupe_key: nil, aggregate_id: user.id,
        payload: { 'user_id' => user.id, 'notify' => true, 'oldest_timestamp' => 50 }
      )
      expect(Achievements::PendingChecks.read(user.id).first).to be_nil
    end

    it 'forwards a retried job once' do
      job = described_class.new(user.id, notify: true)

      2.times { job.perform_now }

      expect(JobOutbox.pending.count).to eq(1)
    end

    it 'a retry whose command is already written keeps every pending timestamp for the next check' do
      described_class.defer(user.id, oldest_timestamp: 50)
      members = Achievements::PendingChecks.read(user.id).last
      job = described_class.new(user.id, notify: true)
      job.perform_now
      Sidekiq.redis { |redis| members.each { redis.call('ZADD', described_class.pending_key(user.id), _1.to_i, _1) } }
      described_class.defer(user.id, oldest_timestamp: 40)

      job.perform_now

      expect(Achievements::PendingChecks.read(user.id).last.map(&:to_i)).to contain_exactly(50, 40)

      described_class.perform_now(user.id, notify: true)

      expect(JobOutbox.pending.map { _1.payload['oldest_timestamp'] }).to contain_exactly(50, 40)
      expect(Achievements::PendingChecks.read(user.id).first).to be_nil
    end

    it 'writes a separate command per job for the same user' do
      2.times { described_class.perform_now(user.id, notify: true) }

      expect(JobOutbox.pending.count).to eq(2)
    end

    it 'keeps the pending timestamps when forwarding raises' do
      described_class.defer(user.id, oldest_timestamp: 50)
      allow(JobOutbox).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid, 'outbox down')

      expect { described_class.perform_now(user.id) }.to raise_error(ActiveRecord::StatementInvalid, 'outbox down')
      expect(Achievements::PendingChecks.read(user.id).first).to eq(50)
    end
  end

  it 'computes even if a legacy installation left its flag disabled' do
    Flipper.disable(:achievements)
    create(:point, user: user, timestamp: 1)

    described_class.perform_now(user.id, notify: true)

    expect(Achievements::Progress.where(user: user)).to be_present
  ensure
    Flipper.remove(:achievements)
  end

  describe '.schedule' do
    it 'collapses a burst of changes into one delayed check' do
      expect { 5.times { |i| described_class.schedule(user.id, oldest_timestamp: 100 + i) } }
        .to have_enqueued_job(described_class).with(user.id).exactly(:once)
    end

    it 'hands the oldest scheduled timestamp to the check' do
      with_current_progress
      [300, 100, 200].each { |timestamp| described_class.schedule(user.id, oldest_timestamp: timestamp) }
      checker = instance_double(Achievements::RegionSetChecker, call: nil)
      allow(Achievements::RegionSetChecker).to receive(:new)
        .with(user, notify: true, oldest_timestamp: 100).and_return(checker)

      described_class.perform_now(user.id)

      expect(checker).to have_received(:call)
    end

    it 'clears the handled timestamps once the check succeeds' do
      described_class.schedule(user.id, oldest_timestamp: 100)
      described_class.perform_now(user.id)

      expect(Achievements::PendingChecks.read(user.id).first).to be_nil
    end

    it 'keeps a change with the same timestamp that arrives during the check' do
      described_class.schedule(user.id, oldest_timestamp: 100)
      checker = instance_double(Achievements::RegionSetChecker)
      allow(checker).to receive(:call) { described_class.schedule(user.id, oldest_timestamp: 100) }
      allow(Achievements::RegionSetChecker).to receive(:new).and_return(checker)

      described_class.perform_now(user.id)

      expect(Achievements::PendingChecks.read(user.id).first).to eq(100)
    end

    it 'schedules again once the pending check has started' do
      described_class.schedule(user.id, oldest_timestamp: 100)
      described_class.perform_now(user.id)

      expect { described_class.schedule(user.id, oldest_timestamp: 200) }
        .to have_enqueued_job(described_class).with(user.id)
    end

    it 'keeps the pending timestamp when the check fails' do
      described_class.schedule(user.id, oldest_timestamp: 100)
      allow(Achievements::RegionSetChecker).to receive(:new).and_raise(StandardError, 'boom')

      expect { described_class.perform_now(user.id) }.to raise_error(StandardError, 'boom')
      expect(Achievements::PendingChecks.read(user.id).first).to eq(100)
    end

    it 'keeps the pending timestamp when the worker shuts down mid-check' do
      described_class.schedule(user.id, oldest_timestamp: 100)
      allow(Achievements::RegionSetChecker).to receive(:new).and_raise(Sidekiq::Shutdown)

      expect { described_class.perform_now(user.id) }.to raise_error(Sidekiq::Shutdown)
      expect(Achievements::PendingChecks.read(user.id).first).to eq(100)
    end

    it 'releases the debounce window after a check' do
      described_class.schedule(user.id)
      described_class.perform_now(user.id)

      expect { described_class.schedule(user.id) }.to have_enqueued_job(described_class).with(user.id)
    end
  end

  describe '.defer' do
    it 'hands the change to the next check without scheduling one' do
      expect { described_class.defer(user.id, oldest_timestamp: 100) }.not_to have_enqueued_job(described_class)
      expect(Achievements::PendingChecks.read(user.id).first).to eq(100)
    end
  end

  context 'with phoenix tables' do
    before { phoenix_state! }

    def checker_for(oldest)
      checker = instance_double(Achievements::RegionSetChecker, call: true)
      allow(Achievements::RegionSetChecker).to receive(:new)
        .with(user, notify: anything, oldest_timestamp: oldest).and_return(checker)
      checker
    end

    it 'schedules one check per burst from the claim row and runs it from the oldest pending timestamp' do
      lock = ActiveRecord::Base.connection.quote(described_class.lock_key(user.id))

      expect do
        described_class.schedule(user.id, oldest_timestamp: 300)
        described_class.schedule(user.id, oldest_timestamp: 100)
      end.to have_enqueued_job(described_class).exactly(:once)
      expect(
        ActiveRecord::Base.connection.select_value("SELECT count(*) FROM phoenix.once_claims WHERE key = #{lock}").to_i
      ).to eq(1)
      expect(Sidekiq.redis { |r| r.exists(described_class.lock_key(user.id)) }).to eq(0)

      checker = checker_for(100)
      described_class.perform_now(user.id)
      expect(checker).to have_received(:call)

      expect(Achievements::PendingChecks.read(user.id)).to eq([nil, nil])
      expect { described_class.schedule(user.id) }.to have_enqueued_job(described_class)
    end

    it "consumes a deferral written by Phoenix's anomaly filter exactly once" do
      source = Rails.root.join('app-phoenix/lib/dawarich/points/anomaly_filter/effects.ex').read
      phoenix_defer = source[/@defer """\n(.*?)\n\s*"""/m, 1]
      ActiveRecord::Base.connection.exec_update(phoenix_defer, 'Phoenix', [user.id, 1_700_000_000, 259_200])

      first = checker_for(1_700_000_000)
      described_class.perform_now(user.id)
      expect(first).to have_received(:call)

      second = checker_for(nil)
      described_class.perform_now(user.id)
      expect(second).to have_received(:call)
    end
  end
end
