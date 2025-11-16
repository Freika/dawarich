# frozen_string_literal: true

module Api
  class PlaceSerializer
    include Alba::Resource

    attributes :id, :name, :latitude, :longitude, :source, :created_at

    attribute :icon do |place|
      place.tags.first&.icon
    end

    attribute :color do |place|
      place.tags.first&.color
    end

    many :tags do
      attributes :id, :name, :icon, :color
    end

    attribute :visits_count do |place|
      place.visits.count
    end
  end
end
