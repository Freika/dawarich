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
    scope :deleted_accounts, -> { where.not(deleted_at: nil) }
  end

  def deleted?
    deleted_at.present?
  end

  def mark_as_deleted!
    update!(deleted_at: Time.current)
  end

  def destroy
    mark_as_deleted!
  end
end
