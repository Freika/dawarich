class AddReviewFieldsToPlaces < ActiveRecord::Migration[8.0]
  def change
    add_column :places, :review_rating, :integer, null: true unless column_exists?(:places, :review_rating)
    add_column :places, :review_text, :text, null: true unless column_exists?(:places, :review_text)
    add_column :places, :review_drafted_at, :datetime, null: true unless column_exists?(:places, :review_drafted_at)
    add_column :places, :review_submitted_at, :datetime, null: true unless column_exists?(:places, :review_submitted_at)
  end
end
