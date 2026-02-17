# frozen_string_literal: true

class AddErrorMessageToExports < ActiveRecord::Migration[8.0]
  def change
    add_column :exports, :error_message, :text
  end
end
