# frozen_string_literal: true

module Achievements
  class CollectionCheckJob < ApplicationJob
    queue_as :achievements

    def perform(user_id, notify: true)
      user = User.find_by(id: user_id)
      CollectionChecker.new(user, notify: notify).call if user&.feature_enabled?(:achievements)
    end
  end
end
