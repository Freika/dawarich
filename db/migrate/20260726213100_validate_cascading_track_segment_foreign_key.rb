# frozen_string_literal: true

class ValidateCascadingTrackSegmentForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  LOCK_TIMEOUT = '5s'
  MAX_ATTEMPTS = 5

  def up
    with_lock_retries { validate_foreign_key :track_segments, :tracks }
  end

  def down; end

  private

  def with_lock_retries
    attempts = 0
    begin
      attempts += 1
      transaction do
        connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
        yield
      end
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
      raise if attempts >= MAX_ATTEMPTS

      sleep(attempts * 5)
      retry
    end
  end
end
