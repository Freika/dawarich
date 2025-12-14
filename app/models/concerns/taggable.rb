# frozen_string_literal: true

module Taggable
  extend ActiveSupport::Concern

  included do
    has_many :taggings, -> { order(created_at: :asc) }, as: :taggable, dependent: :destroy
    has_many :tags, through: :taggings

    scope :with_tags, ->(tag_ids) { joins(:taggings).where(taggings: { tag_id: tag_ids }).distinct }
    scope :with_all_tags, lambda { |tag_ids|
      tag_ids = Array(tag_ids).uniq
      return none if tag_ids.empty?

      # For each tag, join and filter, then use HAVING to ensure all tags are present
      joins(:taggings)
        .where(taggings: { tag_id: tag_ids })
        .group("#{table_name}.id")
        .having('COUNT(DISTINCT taggings.tag_id) = ?', tag_ids.length)
    }
    scope :without_tags, -> { left_joins(:taggings).where(taggings: { id: nil }) }
    scope :tagged_with, lambda { |tag_name, user|
      joins(:tags).where(tags: { name: tag_name, user: user }).distinct
    }
  end

  def add_tag(tag)
    tags << tag unless tags.include?(tag)
  end

  def remove_tag(tag)
    tags.delete(tag)
  end

  def tag_names
    tags.pluck(:name)
  end

  def tagged_with?(tag)
    tags.include?(tag)
  end
end
