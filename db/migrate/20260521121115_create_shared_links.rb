# frozen_string_literal: true

class CreateSharedLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :shared_links, id: :uuid, default: -> { 'gen_random_uuid()' }, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer  :resource_type, null: false
      t.bigint   :resource_id
      t.string   :name, null: false, limit: 255
      t.string   :magic_phrase, limit: 255
      t.datetime :expires_at
      t.datetime :revoked_at
      t.jsonb    :settings, null: false, default: {}
      t.integer  :view_count, null: false, default: 0
      t.datetime :last_accessed_at
      t.timestamps
    end

    add_index :shared_links, %i[resource_type resource_id], where: 'resource_id IS NOT NULL', if_not_exists: true
    add_index :shared_links, :user_id, name: :index_shared_links_active_by_user, where: 'revoked_at IS NULL',
                                        if_not_exists: true

    Rails.logger.info('shared_links table created')
  end
end
