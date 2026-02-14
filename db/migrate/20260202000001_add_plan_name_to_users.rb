# frozen_string_literal: true

class AddPlanNameToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :plan_name, :string, default: 'personal'

    reversible do |dir|
      dir.up do
        if ENV.fetch('SELF_HOSTED', 'true').to_s == 'true'
          User.update_all(plan_name: 'self_hosted')
        end
      end
    end
  end
end
