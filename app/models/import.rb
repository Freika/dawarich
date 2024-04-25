# frozen_string_literal: true

class Import < ApplicationRecord
  belongs_to :user
  has_many :points, dependent: :destroy

  include ImportUploader::Attachment(:raw)

  enum source: { google: 0, owntracks: 1 }
end
