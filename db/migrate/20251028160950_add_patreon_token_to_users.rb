class AddPatreonTokenToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :patreon_access_token, :text
    add_column :users, :patreon_refresh_token, :text
    add_column :users, :patreon_token_expires_at, :datetime
  end
end
