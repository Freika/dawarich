# frozen_string_literal: true

class ActivateSelfhostedUsers < ActiveRecord::Migration[8.0]
  def up
    return unless DawarichSettings.self_hosted?

    User.update_all(status: :active)
  end

  def down
    return unless DawarichSettings.self_hosted?

    User.update_all(status: :inactive)
  end
end
