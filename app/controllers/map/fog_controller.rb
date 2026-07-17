# frozen_string_literal: true

module Map
  class FogController < ApplicationController
    before_action :authenticate_user!
    layout 'map'

    def index
      @start_at = Time.zone.parse('1970-01-01').beginning_of_day
      @end_at = Time.zone.today.end_of_day
    end
  end
end
