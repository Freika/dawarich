# frozen_string_literal: true

class AddFamilyPerformanceIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Index for family invitations queries
    unless index_exists?(:family_invitations, %i[family_id status expires_at],
                         name: 'index_family_invitations_on_family_status_expires')
      add_index :family_invitations, %i[family_id status expires_at],
                name: 'index_family_invitations_on_family_status_expires',
                algorithm: :concurrently
    end

    # Index for family membership queries by role
    unless index_exists?(:family_memberships, %i[family_id role], name: 'index_family_memberships_on_family_and_role')
      add_index :family_memberships, %i[family_id role],
                name: 'index_family_memberships_on_family_and_role',
                algorithm: :concurrently
    end

    # Index for user email lookups in invitations (skip if exists)
    unless index_exists?(:family_invitations, :email)
      add_index :family_invitations, :email,
                name: 'index_family_invitations_on_email',
                algorithm: :concurrently
    end

    # Composite index for active invitations
    unless index_exists?(:family_invitations, %i[status expires_at],
                         name: 'index_family_invitations_on_status_and_expires_at')
      add_index :family_invitations, %i[status expires_at],
                name: 'index_family_invitations_on_status_and_expires_at',
                algorithm: :concurrently
    end
  end
end
