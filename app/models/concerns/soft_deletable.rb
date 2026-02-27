# frozen_string_literal: true

module SoftDeletable
  extend ActiveSupport::Concern

  # Devise overrides must be prepended to take priority over Devise's own
  # method definitions in the ancestor chain.
  module DeviseOverrides
    def active_for_authentication?
      super && !deleted?
    end

    def inactive_message
      deleted? ? :deleted : super
    end
  end

  included do
    prepend DeviseOverrides

    scope :non_deleted, -> { where(deleted_at: nil) }
    scope :deleted, -> { where.not(deleted_at: nil) }
  end

  def deleted?
    deleted_at.present?
  end

  def mark_as_deleted!
    update!(deleted_at: Time.current)
  end

  # Overrides ActiveRecord#destroy to perform soft-delete instead of hard-delete.
  # Intentionally does NOT call super — this prevents dependent: :destroy callbacks
  # from firing. Associated records are cleaned up by Users::Destroy service during
  # the background hard-deletion phase (Users::DestroyJob).
  def destroy
    mark_as_deleted!
  end
end
