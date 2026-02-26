# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  def find_non_deleted_user(user_id)
    user = User.find_by(id: user_id)
    return nil if user.nil? || user.deleted?

    user
  end
end
