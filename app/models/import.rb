class Import < ApplicationRecord
  belongs_to :user
  has_many :points, dependent: :destroy

  has_one_attached :file

  enum source: { google: 0, owntracks: 1 }

  after_create_commit :async_import

  private

  def async_import
    ImportJob.perform_later(user.id, self.id)
  end
end
