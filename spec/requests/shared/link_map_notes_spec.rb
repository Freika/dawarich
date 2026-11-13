# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map notes on shared links', type: :request do
  let(:owner) { create(:user) }
  let(:settings) { { 'start_date' => '2026-04-01', 'end_date' => '2026-04-14', 'show_map_notes' => true } }
  let(:link) do
    create(:shared_link, user: owner, resource_type: :timeline, resource_id: nil, settings: settings,
                         autobuild_trip: false)
  end

  def note(body, at, lat: 48.85, lon: 2.35, **attrs)
    create(:note, user: owner, body: body, noted_at: at, latitude: lat, longitude: lon, **attrs)
  end

  def shared_notes
    get "/s/#{link.id}"
    Capybara.string(response.body).all('[data-testid=shared-note] [data-testid=shared-note-body]').map(&:text)
  end

  describe 'timeline link' do
    before do
      note('Second', Time.utc(2026, 4, 10, 9))
      note('First', Time.utc(2026, 4, 2, 9))
      note('Before the period', Time.utc(2026, 3, 31, 9))
      note('After the period', Time.utc(2026, 4, 15, 9))
    end

    it 'shows the notes of the shared period, oldest first' do
      expect(shared_notes).to eq(%w[First Second])
    end

    it 'shows a note written after the link was created' do
      link
      note('Written later', Time.utc(2026, 4, 12, 9))

      expect(shared_notes).to include('Written later')
    end

    it 'leaves out trip day notes and other users\' notes' do
      trip = create(:trip, user: owner, started_at: Time.utc(2026, 4, 1), ended_at: Time.utc(2026, 4, 14))
      create(:note, user: owner, attachable: trip, body: 'Trip day', noted_at: Time.utc(2026, 4, 3, 12))
      create(:note, body: 'Foreign', noted_at: Time.utc(2026, 4, 3, 12), latitude: 1, longitude: 2)

      expect(shared_notes).to eq(%w[First Second])
    end

    it 'hides a note inside a privacy zone' do
      tag = create(:tag, :privacy_zone, user: owner, privacy_radius_meters: 500)
      home = create(:place, user: owner, name: 'Home', latitude: 52.444, longitude: 13.5, lonlat: 'POINT(13.5 52.444)')
      create(:tagging, tag: tag, taggable: home)
      note('At home', Time.utc(2026, 4, 5, 9), lat: 52.444, lon: 13.5)

      expect(shared_notes).to eq(%w[First Second])
    end

    it 'never exposes where a note was written' do
      get "/s/#{link.id}"

      expect(response.body).not_to include('48.85')
    end

    context 'when the toggle is off' do
      let(:settings) { super().merge('show_map_notes' => false) }

      it 'sends no note text to the page' do
        expect(shared_notes).to eq([])
        expect(response.body).not_to include('First')
      end
    end

    context 'when the toggle was never set' do
      let(:settings) { super().except('show_map_notes') }

      it 'is off' do
        expect(shared_notes).to eq([])
      end
    end

    context 'when the link is limited to one import' do
      let(:settings) { super().merge('import_id' => create(:import, user: owner).id) }

      it 'shows no notes, because a note belongs to no import' do
        expect(shared_notes).to eq([])
      end
    end
  end

  describe 'track link' do
    let(:track) { create(:track, user: owner, start_at: Time.utc(2026, 4, 2, 8), end_at: Time.utc(2026, 4, 2, 10)) }
    let(:link) do
      create(:shared_link, user: owner, resource_type: :track, resource_id: track.id,
                           settings: { 'show_map_notes' => true }, autobuild_trip: false)
    end

    it 'shows the notes written about the time of the track' do
      note('On the way', Time.utc(2026, 4, 2, 9))
      note('That evening', Time.utc(2026, 4, 2, 20))

      expect(shared_notes).to eq(['On the way'])
    end
  end

  %i[trip live].each do |type|
    it "shows no map notes on a #{type} link even if the setting is forced on" do
      note('Anything', 1.hour.ago)
      resource_id = type == :live ? nil : create(:trip, user: owner).id
      forced = create(:shared_link, user: owner, resource_type: type, resource_id: resource_id,
                                    settings: { 'show_map_notes' => true }, autobuild_trip: false)

      get "/s/#{forced.id}"

      expect(response.body).not_to include('Anything')
    end
  end

  describe 'creating a link' do
    before { sign_in owner }

    it 'stores the toggle from the timeline form' do
      post share_links_timeline_path, params: {
        shared_link: { start_date: '2026-04-01', end_date: '2026-04-14', settings: { show_map_notes: '1' } }
      }

      expect(owner.shared_links.timeline.last.settings['show_map_notes']).to be(true)
    end

    it 'offers the toggle with a warning about notes written later' do
      get new_share_links_timeline_path

      expect(response.body).to include('shared_link[settings][show_map_notes]')
      expect(response.body).to include(I18n.t('shared_links.map_notes_toggle.hint'))
    end
  end
end
