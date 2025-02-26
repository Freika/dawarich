# frozen_string_literal: true

class ActivateSelfhostedUsers < ActiveRecord::Migration[8.0]
  def up
    return unless DawarichSettings.self_hosted?

    User.update_all(status: :active) # rubocop:disable Rails/SkipsModelValidations
  end

  def down
    return unless DawarichSettings.self_hosted?

    User.update_all(status: :inactive) # rubocop:disable Rails/SkipsModelValidations
  end
end
