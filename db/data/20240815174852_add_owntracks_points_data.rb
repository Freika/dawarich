# frozen_string_literal: true

class AddOwntracksPointsData < ActiveRecord::Migration[7.1]
  def up
    Import.owntracks.each do |import|
      import.points.each do |point|
        params = OwnTracks::Params.new(point.raw_data).call

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
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
