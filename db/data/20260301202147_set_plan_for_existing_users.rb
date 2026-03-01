# frozen_string_literal: true

class SetPlanForExistingUsers < ActiveRecord::Migration[8.0]
  def up
    if DawarichSettings.self_hosted?
      # Self-hosted: all users get self_hoster plan (already the default 0)
      # Explicit update for clarity in case any user has a non-default value
      User.update_all(plan: :self_hoster)
    else
      # Cloud: active/trial users get pro plan (the current plan, renamed)
      User.where(status: %i[active trial]).update_all(plan: :pro)
      # Inactive Cloud users default to self_hoster (0) which is fine —
      # they'll get a proper plan assigned when they resubscribe
    end
  end

  def down
    User.update_all(plan: :self_hoster)
  end
end
