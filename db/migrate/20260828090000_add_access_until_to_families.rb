# frozen_string_literal: true

class AddAccessUntilToFamilies < ActiveRecord::Migration[8.0]
  def change
    add_column :families, :access_until, :datetime
  end
end
