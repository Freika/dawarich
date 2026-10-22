# frozen_string_literal: true

class Families::AutoCreationJob < ApplicationJob
  queue_as :families

  def perform(user_id)
    user = User.find_by(id: user_id)

    return unless user

    Families::AutoCreate.new(user: user).call
  end
end
