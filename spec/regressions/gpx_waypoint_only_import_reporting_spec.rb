# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reporting for GPX files that contain waypoints but no track' do
  let(:user) { create(:user) }

  def import_file(filename)
    import = create(:import, user:, name: filename, source: 'gpx')
    import.file.attach(
      io: Rails.root.join('spec/fixtures/files/gpx', filename).open,
      filename: filename,
      content_type: 'application/gpx+xml'
    )
    Imports::Create.new(user, import).call
    import.reload
  end

  def last_notification_content
    user.notifications.order(:created_at).last.content
  end

  context 'when the file holds only waypoints' do
    it 'names waypoints as the reason instead of blaming absent timestamps' do
      import = import_file('gpx_waypoints_only.gpx')

      expect(import.points.count).to eq(0)
      expect(last_notification_content).to match(/waypoint/i)
      expect(last_notification_content).to include('3')
      expect(last_notification_content).not_to match(/timestamp/i)
    end

    it 'records the number of waypoints it saw' do
      import = import_file('gpx_waypoints_only.gpx')

      expect(import.raw_data['waypoints_seen']).to eq(3)
    end
  end

  context 'when every waypoint carries a time' do
    it 'still does not attribute the empty import to missing timestamps' do
      import_file('gpx_waypoints_with_time.gpx')

      expect(last_notification_content).to match(/waypoint/i)
      expect(last_notification_content).not_to match(/timestamp/i)
    end
  end

  context 'when the file holds trackpoints without times' do
    it 'keeps the existing timestamp guidance' do
      import_file('gpx_track_no_timestamps.gpx')

      expect(last_notification_content).to match(/timestamp/i)
      expect(last_notification_content).not_to match(/waypoint/i)
    end
  end
end
