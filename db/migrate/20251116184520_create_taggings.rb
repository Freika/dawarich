# frozen_string_literal: true

class CreateTaggings < ActiveRecord::Migration[8.0]
  def change
    create_table :taggings do |t|
      t.references :taggable, polymorphic: true, null: false, index: true
      t.references :tag, null: false, foreign_key: true, index: true

      t.timestamps
    end

    add_index :taggings, %i[taggable_type taggable_id tag_id], unique: true,
name: 'index_taggings_on_taggable_and_tag'
  end
end
