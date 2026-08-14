# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports surface zero points with no timestamps', type: :request do
  let(:user) { create(:user) }

  def build_import_with(file_path, name:, source:, content_type:)
    import = create(:import, user: user, name: name, source: source, skip_background_processing: true)
    import.file.attach(
      io: File.open(file_path, 'rb'),
      filename: name,
      content_type: content_type
    )
    import
  end

  context 'when a GPX file has trackpoints but no per-point timestamps' do
    let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_track_no_timestamps.gpx') }

    it 'imports no points and tells the user the file lacks timestamps' do
      import = build_import_with(
        file_path, name: 'no_timestamps.gpx', source: :gpx, content_type: 'application/gpx+xml'
      )

      Imports::Create.new(user, import).call

      import.reload
      expect(import.points.count).to eq(0)
      expect(import.doubles).to eq(0)
      expect(import.status).to eq('completed')

      notification = user.notifications.order(:created_at).last
      expect(notification).not_to be_nil
      expect(notification.kind).to eq('warning')
      expect(notification.content).to include('no_timestamps.gpx')
      expect(notification.content).to include('0 points')
      expect(notification.content).to include('&lt;time&gt;/&lt;when&gt;')
    end

    it 'uses the user language when the import runs in the background' do
      user.update!(settings: { 'locale' => 'fr' })
      import = build_import_with(
        file_path, name: 'sans_horodatage.gpx', source: :gpx, content_type: 'application/gpx+xml'
      )

      I18n.with_locale(:en) { Import::ProcessJob.perform_now(import.id) }

      notification = user.notifications.order(:created_at).last
      expect(notification.title).to eq('Importation terminée sans point')
      expect(notification.content).to include('sans_horodatage.gpx')
      expect(notification.content).to include("n'a importé aucun point")
      expect(notification.content).to include('&lt;time&gt;/&lt;when&gt;')

      sign_in user
      get notification_url(notification)

      rendered_notification = Nokogiri::HTML(response.body).at_css("#notification_#{notification.id}")
      expect(rendered_notification.text).to include('<time>/<when>')
    end
  end

  context 'when a non-GPX source imports zero new points with zero doubles' do
    let(:file_path) { Rails.root.join('spec/fixtures/files/google/semantic_history.json') }

    it 'notifies the user without blaming missing timestamps' do
      first = build_import_with(
        file_path, name: 'semantic_history_1.json', source: :google_semantic_history,
                   content_type: 'application/json'
      )
      Imports::Create.new(user, first).call
      expect(first.reload.points.count).to be_positive

      second = build_import_with(
        file_path, name: 'semantic_history_2.json', source: :google_semantic_history,
                   content_type: 'application/json'
      )
      Imports::Create.new(user, second).call

      second.reload
      expect(second.points.count).to eq(0)
      expect(second.doubles).to eq(0)
      expect(second.status).to eq('completed')

      notification = user.notifications.order(:created_at).last
      expect(notification).not_to be_nil
      expect(notification.kind).to eq('warning')
      expect(notification.content).to include('semantic_history_2.json')
      expect(notification.content).to include('0 points')
      expect(notification.content).not_to include('timestamps')
      expect(notification.content).not_to include('&lt;time&gt;/&lt;when&gt;')
    end
  end
end
