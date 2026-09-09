# frozen_string_literal: true

# Accounts created after detection v3 only ever have v3 output, so they are
# born re-detected — without this, confidence gating and the tighter timeline
# gap bar would never activate for new signups.
class DefaultVisitsRedetectedAtForNewAccounts < ActiveRecord::Migration[8.0]
  def up
    change_column_default :users, :visits_redetected_at, from: nil, to: -> { 'CURRENT_TIMESTAMP' }
  end

  def down
    change_column_default :users, :visits_redetected_at, from: -> { 'CURRENT_TIMESTAMP' }, to: nil
  end
end
