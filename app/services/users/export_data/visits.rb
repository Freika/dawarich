# frozen_string_literal: true

class Users::ExportData::Visits
  def initialize(user)
    @user = user
  end

  def call
    user.visits.includes(:place).map do |visit|
      visit_hash = visit.as_json(except: %w[user_id place_id id])

      if visit.place
        visit_hash['place_reference'] = {
          'name' => visit.place.name,
          'latitude' => visit.place.lat.to_s,
          'longitude' => visit.place.lon.to_s,
          'source' => visit.place.source
        }
      else
        visit_hash['place_reference'] = nil
      end

      visit_hash
    end
  end

  private

  attr_reader :user
end
