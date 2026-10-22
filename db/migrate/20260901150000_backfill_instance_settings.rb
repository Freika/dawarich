# frozen_string_literal: true

class BackfillInstanceSettings < ActiveRecord::Migration[8.0]
  def up
    InstanceSettings::Backfill.call
  end

  # Removes only what the backfill could have written, and only while it is
  # still untouched — an operator who has since edited a value in the admin page
  # should keep it.
  def down
    InstanceSetting.where(key: InstanceSettings::Registry.keys.map(&:to_s))
                   .where('created_at = updated_at')
                   .delete_all
  end
end
