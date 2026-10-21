# frozen_string_literal: true

class Families::AutoCreationJob < ApplicationJob
  queue_as :families

  def perform(user_id)
    Families::JobCommands.execute('auto_create', user_id, job_id: job_id) do
      user = User.find_by(id: user_id)
      Families::AutoCreate.new(user: user).call if user
    end
  end
end
