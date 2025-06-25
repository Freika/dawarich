# frozen_string_literal: true

class Users::ExportData::Points
  def initialize(user)
    @user = user
  end

  def call
    points_data = Point.where(user_id: user.id).order(id: :asc).as_json(except: %w[user_id])

    return [] if points_data.empty?

    # Get unique IDs for batch loading
    import_ids = points_data.filter_map { |row| row['import_id'] }.uniq
    country_ids = points_data.filter_map { |row| row['country_id'] }.uniq
    visit_ids = points_data.filter_map { |row| row['visit_id'] }.uniq

    # Load all imports in one query
    imports_map = {}
    if import_ids.any?
      Import.where(id: import_ids).find_each do |import|
        imports_map[import.id] = {
          'name' => import.name,
          'source' => import.source,
          'created_at' => import.created_at.iso8601
        }
      end
    end

    # Load all countries in one query
    countries_map = {}
    if country_ids.any?
      Country.where(id: country_ids).find_each do |country|
        countries_map[country.id] = {
          'name' => country.name,
          'iso_a2' => country.iso_a2,
          'iso_a3' => country.iso_a3
        }
      end
    end

    # Load all visits in one query
    visits_map = {}
    if visit_ids.any?
      Visit.where(id: visit_ids).find_each do |visit|
        visits_map[visit.id] = {
          'name' => visit.name,
          'started_at' => visit.started_at&.iso8601,
          'ended_at' => visit.ended_at&.iso8601
        }
      end
    end

    # Build the final result
    points_data.map do |row|
      point_hash = row.except('import_id', 'country_id', 'visit_id', 'id').to_h

      # Add relationship references
      point_hash['import_reference'] = imports_map[row['import_id']]
      point_hash['country_info'] = countries_map[row['country_id']]
      point_hash['visit_reference'] = visits_map[row['visit_id']]

      point_hash
    end
  end

  private

  attr_reader :user
end
