# frozen_string_literal: true

class AddErrorMessageToImports < ActiveRecord::Migration[8.0]
  def change
    add_column :imports, :error_message, :text
  end
end
