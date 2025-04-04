# frozen_string_literal: true

class SetActiveUntilForSelfhostedUsers < ActiveRecord::Migration[8.0]
  def up
    return unless DawarichSettings.self_hosted?

    # rubocop:disable Rails/SkipsModelValidations
    User.where(active_until: nil).update_all(active_until: 1000.years.from_now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
