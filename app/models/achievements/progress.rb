# frozen_string_literal: true

module Achievements
  class Progress < ApplicationRecord
    self.table_name = 'achievement_progresses'

    EXPLORATION_KEY = 'exploration'

    belongs_to :user

    validates :achievement_key, presence: true, uniqueness: { scope: :user_id }

    def self.exploration_for(user)
      find_or_initialize_by(user_id: user.id, achievement_key: EXPLORATION_KEY)
    end
  end
end
