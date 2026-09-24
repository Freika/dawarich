# frozen_string_literal: true

class Countries::VisitedQuery
  def initialize(user:, start_at:, end_at:, import_id: nil)
    @user = user
    @start_at = start_at.to_i
    @end_at = end_at.to_i
    @import_id = import_id.presence
  end

  def call
    rows = relation.distinct.pluck(:country_id, :country_name, :country)
    countries = Country.where(id: rows.filter_map(&:first).uniq).index_by(&:id)

    visited = rows.filter_map do |country_id, country_name, legacy_country|
      country = countries[country_id]
      name = country&.name || country_name.presence || legacy_country.presence
      next if name.blank?

      iso_a3 = country&.iso_a3 || Countries::IsoCodeMapper.iso_codes_from_country_name(name).last
      next if iso_a3.blank?

      { iso_a3: iso_a3, name: country&.name || Countries::NameAliases.canonical(name) }
    end

    visited.uniq { |item| item[:iso_a3] }.sort_by { |item| item[:iso_a3] }
  end

  private

  attr_reader :user, :start_at, :end_at, :import_id

  def relation
    scope = user.scoped_points.without_raw_data.not_anomaly.where(timestamp: start_at..end_at)
    scope = scope.where(import_id: import_id) if import_id
    scope
  end
end
