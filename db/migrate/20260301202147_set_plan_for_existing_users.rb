# frozen_string_literal: true

class SetPlanForExistingUsers < ActiveRecord::Migration[8.0]
  # Raw SQL on purpose: touching the User AR model here loads its current
  # schema and pending enum decorators (e.g. `subscription_source`), which
  # reference columns added by later migrations. Upgrading from older
  # versions in a single run would crash with "Undeclared attribute type
  # for enum 'subscription_source'". See issue #2576.
  #
  # status enum: 0 = inactive, 1 = active, 2 = trial
  # plan enum:   0 = lite,     1 = pro
  def up
    if DawarichSettings.self_hosted?
      execute 'UPDATE users SET plan = 1'
    else
      execute 'UPDATE users SET plan = 1 WHERE status IN (1, 2)'
      execute 'UPDATE users SET plan = 0 WHERE status = 0'
    end
  end

  def down
    # No-op: we don't want to revert users back to the old plan values
  end
end
