# frozen_string_literal: true

class PlaceVisit < ApplicationRecord
  belongs_to :place
  belongs_to :visit
end
