# frozen_string_literal: true

module Visits
  # Finds visits in a selected area on the map
  class Finder
    def initialize(user, params)
      @user = user
      @params = params
    end

    def call
      if area_selected?
        Visits::FindWithinBoundingBox.new(user, params).call
      else
        Visits::FindInTime.new(user, params).call
      end
    end

    private

    attr_reader :user, :params

    def area_selected?
      params[:selection] == 'true' &&
        params[:sw_lat].present? &&
        params[:sw_lng].present? &&
        params[:ne_lat].present? &&
        params[:ne_lng].present?
    end
  end
end
