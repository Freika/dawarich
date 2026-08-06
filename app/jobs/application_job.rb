# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  private

  # Look up a user by ID, returning nil (and logging) if not found.
  # Respects the default scope, so soft-deleted users are excluded.
  # Use in perform methods: `user = find_user_or_skip(user_id) || return`
  def find_user_or_skip(user_id)
    User.find_by(id: user_id).tap do |user|
      Rails.logger.info "#{self.class.name}: User #{user_id} not found, skipping" unless user
    end
  end
end
