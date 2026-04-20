class AddSubscriptionSourceAndSignupVariantToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :subscription_source, :integer, default: 0, null: false
    add_column :users, :signup_variant, :string
    add_index :users, :subscription_source
  end
end
