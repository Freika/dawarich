# frozen_string_literal: true

class UsersMailerPreview < ActionMailer::Preview
  def welcome
    UsersMailer.with(user: User.last).welcome
  end

  def explore_features
    UsersMailer.with(user: User.last).explore_features
  end

  # Transitional previews — remove after 2026-05-17 along with the
  # corresponding mailer methods and templates.
  def trial_expires_soon
    UsersMailer.with(user: User.last).trial_expires_soon
  end

  def trial_expired
    UsersMailer.with(user: User.last).trial_expired
  end

  def post_trial_reminder_early
    UsersMailer.with(user: User.last).post_trial_reminder_early
  end

  def post_trial_reminder_late
    UsersMailer.with(user: User.last).post_trial_reminder_late
  end
end
