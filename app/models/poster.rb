# frozen_string_literal: true

class Poster < ApplicationRecord
  belongs_to :user

  enum :status, { created: 0, processing: 1, completed: 2, failed: 3 }

  validates :name, presence: true

  has_one_attached :image
  has_one_attached :print_pdf

  after_commit -> { Posters::CreateJob.perform_later(id) }, on: :create
  after_update_commit :broadcast_status_change

  private

  def broadcast_status_change
    broadcast_replace_to(
      [user, :posters],
      target: ActionView::RecordIdentifier.dom_id(self),
      partial: 'posters/poster',
      locals: { poster: self }
    )
  end
end
