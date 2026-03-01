# frozen_string_literal: true

class SetPlanForExistingUsers < ActiveRecord::Migration[8.0]
  def up
    if DawarichSettings.self_hosted?
      # Self-hosted: all users get pro plan (already the default 1)
      # Explicit update for clarity in case any user has a non-default value
      User.update_all(plan: :pro)
    else
      # Cloud: active/trial users get pro plan (the current plan, renamed)
      User.where(status: %i[active trial]).update_all(plan: :pro)
      User.where(status: :inactive).update_all(plan: :lite)
    end
  end

  def down
    # No-op: we don't want to revert users back to the old plan values
  end
end
