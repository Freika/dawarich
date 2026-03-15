# frozen_string_literal: true

module SoftDeletable
  extend ActiveSupport::Concern

  # WARNING: This concern adds a default_scope that excludes soft-deleted records.
  # Use User.unscoped or User.deleted to access soft-deleted records.

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

    default_scope { where(deleted_at: nil) }
    scope :deleted, -> { unscoped.where.not(deleted_at: nil) }
  end

  def deleted?
    deleted_at.present?
  end

  def mark_as_deleted!
    update!(deleted_at: Time.current)
  end

  # Atomic soft-delete that prevents race conditions.
  # Returns true if this caller performed the soft-delete, false if already deleted.
  # Uses UPDATE ... WHERE deleted_at IS NULL to guarantee only one caller wins.
  def mark_as_deleted_atomically!
    now = Time.current
    rows_updated = self.class.unscoped.where(id: id, deleted_at: nil)
                       .update_all(deleted_at: now)

    if rows_updated.positive?
      self.deleted_at = now
      true
    else
      false
    end
  end

  # Override reload to use unscoped so soft-deleted records can still be refreshed.
  # Without this, user.reload after soft-deletion raises RecordNotFound because
  # the default scope excludes the record.
  def reload(options = nil)
    self.class.unscoped { super }
  end

  # Overrides ActiveRecord#destroy to perform soft-delete instead of hard-delete.
  # Intentionally does NOT call super — this prevents dependent: :destroy callbacks
  # from firing. Associated records are cleaned up by Users::Destroy service during
  # the background hard-deletion phase (Users::DestroyJob).
  def destroy
    mark_as_deleted!
  end
end
