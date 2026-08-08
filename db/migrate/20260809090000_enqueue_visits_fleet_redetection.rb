# frozen_string_literal: true

class EnqueueVisitsFleetRedetection < ActiveRecord::Migration[8.0]
  def up
    return unless defined?(DawarichSettings) && DawarichSettings.self_hosted?

    Visits::FleetRedetectJob.perform_later if defined?(Visits::FleetRedetectJob)
  end

  def down; end
end
