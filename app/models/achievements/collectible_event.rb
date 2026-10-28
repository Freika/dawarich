# frozen_string_literal: true

module Achievements
  class CollectibleEvent < ApplicationRecord
    self.table_name = 'achievement_collectible_events'

    belongs_to :collectible
    validates :kind, inclusion: { in: %w[earned revoked] }
  end
end
