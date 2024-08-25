# frozen_string_literal: true

class AddOwntracksPointsData < ActiveRecord::Migration[7.1]
  def up
    Rails.logger.info("Updating #{Import.owntracks.count} owntracks imports points")

    import_points = 0
    Import.owntracks.each do |import|
      import.points.each do |point|
        params = OwnTracks::Params.new(point.raw_data).call

        update_point(point, params)

        import_points += 1
      end
    end

    Rails.logger.info("#{import_points} points updated from owntracks imports")

    # Getting points by owntracks-specific data
    points = Point.where("raw_data -> 'm' is not null and raw_data -> 'acc' is not null")

    Rails.logger.info("Updating #{points.count} points")

    points_updated = 0
    points.each do |point|
      params = OwnTracks::Params.new(point.raw_data).call

      update_point(point, params)

      points_updated += 1
    end

    Rails.logger.info("#{points_updated} points updated")
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def update_point(point, params)
    point.update!(
      battery:            params[:battery],
      ping:               params[:ping],
      altitude:           params[:altitude],
      accuracy:           params[:accuracy],
      vertical_accuracy:  params[:vertical_accuracy],
      velocity:           params[:velocity],
      ssid:               params[:ssid],
      bssid:              params[:bssid],
      tracker_id:         params[:tracker_id],
      inrids:             params[:inrids],
      in_regions:         params[:in_regions],
      topic:              params[:topic],
      battery_status:     params[:battery_status],
      connection:         params[:connection],
      trigger:            params[:trigger]
    )
  end
end
