# frozen_string_literal: true

class CreateHomes < ActiveRecord::Migration[8.0]
  def change
    create_table :homes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :place, null: false, foreign_key: { on_delete: :cascade }
      t.date :started_on
      t.date :ended_on

      t.timestamps
    end

    add_check_constraint :homes,
                         'ended_on IS NULL OR started_on IS NULL OR ended_on >= started_on',
                         name: 'homes_end_not_before_start'
  end
end
