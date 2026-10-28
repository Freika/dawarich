# frozen_string_literal: true

class Exploration::State < ApplicationRecord
  self.table_name = 'exploration_states'

  scope :activated, -> { where.not(activated_at: nil) }
end
