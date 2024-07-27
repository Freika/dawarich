# frozen_string_literal: true

class AreaVisitsCalculatingJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)
    areas = user.areas

    Visits::Areas::Calculate(user, areas).call
  end
end
