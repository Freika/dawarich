# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::RestoreUserJob, :non_transactional, threads: 2 do
  it 'raises instead of silently completing when another worker holds the lock' do
    user = create(:user, points_archive_state: :restoring)
    lock_name = "points_archival:#{user.id}"
    acquired = Queue.new
    release = Queue.new

    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.with_advisory_lock(lock_name, timeout_seconds: 0) do
          acquired << true
          release.pop
        end
      end
    end

    acquired.pop

    expect { described_class.new.perform(user.id) }
      .to raise_error(WithAdvisoryLock::FailedToAcquireLock)
    expect(user.reload.points_archive_state_restoring?).to be(true)

    release << true
    holder.join
  ensure
    user&.destroy
  end
end
