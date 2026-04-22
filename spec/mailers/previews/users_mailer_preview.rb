# frozen_string_literal: true

class UsersMailerPreview < ActionMailer::Preview
  def welcome
    UsersMailer.with(user: User.last).welcome
  end

  def explore_features
    UsersMailer.with(user: User.last).explore_features
  end
end
