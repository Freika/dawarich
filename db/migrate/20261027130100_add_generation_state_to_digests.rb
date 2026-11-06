# frozen_string_literal: true

class AddGenerationStateToDigests < ActiveRecord::Migration[8.0]
  def up
    add_column :digests, :generation_status, :integer, default: 0, null: false, if_not_exists: true
  end

  def down
    remove_column :digests, :generation_status, if_exists: true
  end
end
