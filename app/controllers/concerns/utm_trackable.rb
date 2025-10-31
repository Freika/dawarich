# frozen_string_literal: true

module UtmTrackable

  extend ActiveSupport::Concern

  UTM_PARAMS = %w[utm_source utm_medium utm_campaign utm_term utm_content].freeze

  def store_utm_params
    UTM_PARAMS.each do |param|
      session[param] = params[param] if params[param].present?
    end
  end

  def assign_utm_params(record)
    utm_data = extract_utm_data_from_session

    return unless utm_data.any?

    record.update_columns(utm_data)
    clear_utm_session
  end

  private

  def extract_utm_data_from_session
    UTM_PARAMS.each_with_object({}) do |param, hash|
      hash[param] = session[param] if session[param].present?
    end
  end

  def clear_utm_session
    UTM_PARAMS.each { |param| session.delete(param) }
  end
end
