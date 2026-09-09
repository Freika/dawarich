# frozen_string_literal: true

# The column predates detection v3 (it was the redetect-button cooldown), so
# a stamp set under the old detector must not unlock v3-only behavior like
# the tighter timeline gap threshold. Cleared here; every v3 redetect path
# stamps it again on completion.
class ResetVisitsRedetectedAtForDetectionV3 < ActiveRecord::Migration[8.0]
  def up
    execute('UPDATE users SET visits_redetected_at = NULL WHERE visits_redetected_at IS NOT NULL')
  end

  def down; end
end
