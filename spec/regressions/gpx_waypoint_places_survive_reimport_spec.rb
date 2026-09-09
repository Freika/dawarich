# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Re-importing a favourites file does not duplicate its places' do
  let(:user) { create(:user) }

  def import_favourites(label)
    filename = 'gpx_waypoints_only.gpx'
    path = Rails.root.join('spec/fixtures/files/gpx', filename)
    import = create(:import, user: user, source: :gpx, name: "#{label}-#{filename}")
    import.file.attach(io: File.open(path), filename: filename, content_type: 'application/gpx+xml')
    EnhancedImport::ExtractJob.new.perform(import.id)
    import
  end

  it 'keeps one place per waypoint when the watcher re-imports the same file' do
    import_favourites('first')
    expect(Place.where(user_id: user.id).count).to eq(3)

    import_favourites('second')

    expect(Place.where(user_id: user.id).count).to eq(3)
  end

  it 'does not create a second tag on the second run' do
    import_favourites('first')
    import_favourites('second')

    expect(user.tags.where(name: 'Food').count).to eq(1)
  end
end
