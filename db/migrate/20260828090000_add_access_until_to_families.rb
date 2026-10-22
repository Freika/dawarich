# frozen_string_literal: true

class AddAccessUntilToFamilies < ActiveRecord::Migration[8.0]
  def up
    return if column_exists?(:families, :access_until)

    add_column :families, :access_until, :datetime
  end

  def down
    return unless column_exists?(:families, :access_until)

    remove_column :families, :access_until
  end
end
