# frozen_string_literal: true

# Instances upgrading from a release that registered :poster_ordering already
# carry the flag row, so FeatureFlags.apply_defaults! leaves it alone and they
# would stay opted out of a feature that now ships on. Switch them on once
# here; turning it back off at /admin/flipper afterwards sticks.
class EnablePosterOrderingFlag < ActiveRecord::Migration[8.0]
  def up
    Flipper.enable(:poster_ordering)
  end

  def down
    Flipper.disable(:poster_ordering)
  end
end
