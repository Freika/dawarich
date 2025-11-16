# frozen_string_literal: true

module Taggable
  extend ActiveSupport::Concern

  included do
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :tags, through: :taggings

    scope :with_tags, ->(tag_ids) { joins(:taggings).where(taggings: { tag_id: tag_ids }).distinct }
    scope :tagged_with, ->(tag_name, user) {
      joins(:tags).where(tags: { name: tag_name, user: user }).distinct
    }
  end

  # Add a tag to this taggable record
  def add_tag(tag)
    tags << tag unless tags.include?(tag)
  end

  # Remove a tag from this taggable record
  def remove_tag(tag)
    tags.delete(tag)
  end

  # Get all tag names for this taggable record
  def tag_names
    tags.pluck(:name)
  end

  # Check if tagged with specific tag
  def tagged_with?(tag)
    tags.include?(tag)
  end
end
