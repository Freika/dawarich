# frozen_string_literal: true

class UsersMailerPreview < ActionMailer::Preview
  def welcome
    UsersMailer.with(user: User.last).welcome
  end

  def explore_features
    UsersMailer.with(user: User.last).explore_features
  end

  def trial_expires_soon
    UsersMailer.with(user: User.last).trial_expires_soon
  end

  def trial_expired
    UsersMailer.with(user: User.last).trial_expired
  end
end
