# frozen_string_literal: true

class Tagging < ApplicationRecord
  belongs_to :taggable, polymorphic: true
  belongs_to :tag

  validates :taggable, presence: true
  validates :tag, presence: true
  validates :tag_id, uniqueness: { scope: [:taggable_type, :taggable_id] }
end
