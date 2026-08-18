# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Anomaly recalculation dispatcher' do
  let(:queued_key) { DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY }
  let(:done_key)   { DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY }
  let(:failed_key) { DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY }

  def with_points(user)
    create(:point, user: user)
    user
  end

  describe 'a user that has been given up on' do
    it 'is not handed out again' do
      user = with_points(create(:user, settings: { 'gps_filtering_enabled' => true }))

      DataMigrations::RecalculateAnomaliesUserJob.mark_failed([user.id])

      runnable, skipped = described_dispatcher.send(:next_users, 5)

      expect(runnable).not_to include(user.id)
      expect(skipped).not_to include(user.id)
    end

    # A rebuild that outlives the staleness window is handed to a second worker,
    # which waits on the lock the first still holds and eventually gives up. It
    # must not brand a user whose rebuild has meanwhile succeeded.
    it 'is not marked failed once the rebuild has already succeeded' do
      user = with_points(create(:user, settings: { 'gps_filtering_enabled' => true }))
      user.update!(settings: user.settings.merge(done_key => Time.current.utc.iso8601))

      DataMigrations::RecalculateAnomaliesUserJob.mark_failed([user.id])

      expect(user.reload.settings).not_to have_key(failed_key)
    end

    it 'keeps the claim so the scan skips it rather than re-queueing it' do
      user = with_points(create(:user, settings: { 'gps_filtering_enabled' => true }))
      described_dispatcher.send(:claim, [user.id])

      DataMigrations::RecalculateAnomaliesUserJob.mark_failed([user.id])

      expect(user.reload.settings).to include(queued_key, failed_key)
    end
  end

  describe 'a claim left behind by a killed worker' do
    it 'is taken back once it is older than the staleness window' do
      user = with_points(create(:user, settings: { 'gps_filtering_enabled' => true }))
      stale = (DataMigrations::RecalculateAnomaliesJob::STALE_CLAIM_AFTER + 1.hour).ago.utc.iso8601
      user.update!(settings: user.settings.merge(queued_key => stale))

      runnable, = described_dispatcher.send(:next_users, 5)

      expect(runnable).to include(user.id)
    end

    it 'is re-stamped by the claim statement, not silently refused' do
      user = with_points(create(:user, settings: { 'gps_filtering_enabled' => true }))
      stale = (DataMigrations::RecalculateAnomaliesJob::STALE_CLAIM_AFTER + 1.hour).ago.utc.iso8601
      user.update!(settings: user.settings.merge(queued_key => stale))

      expect(described_dispatcher.send(:claim, [user.id])).to eq([user.id])
      expect(user.reload.settings[queued_key]).to be > stale
    end

    it 'is left alone while the claim is still fresh' do
      user = with_points(create(:user, settings: { 'gps_filtering_enabled' => true }))
      described_dispatcher.send(:claim, [user.id])

      runnable, = described_dispatcher.send(:next_users, 5)

      expect(runnable).not_to include(user.id)
    end

    # config.time_zone defaults to Europe/Berlin and is settable per instance, so
    # a claim can carry a "+02:00" or "-07:00" offset. Comparing those as text
    # sorts them by wall-clock digits, which on any zone behind UTC makes a claim
    # written a second ago look older than a UTC cutoff.
    it 'is left alone when a fresh claim carries an offset from a zone behind UTC' do
      user = with_points(create(:user, settings: { 'gps_filtering_enabled' => true }))
      fresh_but_offset = Time.current.in_time_zone('America/Los_Angeles').iso8601
      user.update!(settings: user.settings.merge(queued_key => fresh_but_offset))

      runnable, = described_dispatcher.send(:next_users, 5)

      expect(runnable).not_to include(user.id)
    end

    it 'is taken back when an offset-formatted claim really is old' do
      user = with_points(create(:user, settings: { 'gps_filtering_enabled' => true }))
      old = (DataMigrations::RecalculateAnomaliesJob::STALE_CLAIM_AFTER + 1.hour)
            .ago.in_time_zone('America/Los_Angeles').iso8601
      user.update!(settings: user.settings.merge(queued_key => old))

      runnable, = described_dispatcher.send(:next_users, 5)

      expect(runnable).to include(user.id)
    end

    # Nothing writes these shapes; they are the corruption cases. A claim nobody
    # can date must fall back to reclaimable rather than raising on the cast or
    # leaving the user claimable by nobody.
    ['not-a-timestamp', '2026-08-02T', '2026-08-02Tfoo', '', nil].each do |bad|
      it "is taken back, not raised on, when the timestamp is #{bad.inspect}" do
        user = with_points(create(:user, settings: { 'gps_filtering_enabled' => true }))
        user.update!(settings: user.settings.merge(queued_key => bad))

        runnable, = described_dispatcher.send(:next_users, 5)

        expect(runnable).to include(user.id)
      end
    end

    it 'is not taken back once the rebuild finished' do
      user = with_points(create(:user, settings: { 'gps_filtering_enabled' => true }))
      stale = (DataMigrations::RecalculateAnomaliesJob::STALE_CLAIM_AFTER + 1.hour).ago.utc.iso8601
      user.update!(settings: user.settings.merge(queued_key => stale, done_key => stale))

      runnable, = described_dispatcher.send(:next_users, 5)

      expect(runnable).not_to include(user.id)
    end
  end

  def described_dispatcher
    @described_dispatcher ||= DataMigrations::RecalculateAnomaliesJob.new
  end
end
