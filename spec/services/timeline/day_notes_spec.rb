# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Timeline::DayAssembler, 'map notes' do
  let(:user) { create(:user) }
  let(:day) { Time.zone.parse('2025-01-15 00:00:00') }
  let(:masker) { Maps::PrivacyZoneMasker.none }

  def assemble(masker: self.masker, from: day, to: day + 1.day)
    described_class.new(user, start_at: from.iso8601, end_at: to.iso8601, privacy_zone_masker: masker).call
  end

  def create_visit(name, from, to)
    place = create(:place, :with_geodata, user: user, name: name)
    create(:visit, user: user, place: place, name: name, started_at: day + from, ended_at: day + to,
                   duration: ((to - from) / 60).to_i)
  end

  it 'lists the day\'s map notes in order, apart from the entries' do
    create_visit('Home', 7.hours, 8.hours)
    create(:note, user: user, body: 'Later', noted_at: day + 15.hours, latitude: 52.5, longitude: 13.4)
    create(:note, user: user, body: 'Earlier', noted_at: day + 9.hours, latitude: 52.5, longitude: 13.4)

    result = assemble.first

    expect(result[:notes].pluck(:body)).to eq(%w[Earlier Later])
    expect(result[:notes].first).to include(latitude: 52.5, longitude: 13.4)
    expect(Time.iso8601(result[:notes].first[:noted_at])).to eq(day + 9.hours)
    expect(result[:entries].pluck(:type)).to eq(['visit'])
  end

  it 'returns a day that has a note but no visit or track' do
    create(:note, user: user, body: 'Quiet day', noted_at: day + 10.hours, latitude: 52.5, longitude: 13.4)

    result = assemble

    expect(result.pluck(:date)).to eq(['2025-01-15'])
    expect(result.first[:entries]).to eq([])
    expect(result.first[:summary][:facts]).to be_nil
  end

  it 'puts a note on the user\'s local day' do
    user.update!(settings: user.settings.merge('timezone' => 'Asia/Tokyo'))
    create(:note, user: user, body: 'Late', noted_at: Time.utc(2025, 1, 15, 16, 30), latitude: 35.6, longitude: 139.7)

    result = assemble(from: Time.utc(2025, 1, 15), to: Time.utc(2025, 1, 17))

    expect(result.pluck(:date)).to eq(['2025-01-16'])
  end

  it 'leaves trip day notes and other users\' notes out' do
    create(:note, :trip_day, user: user)
    create(:note, body: 'Foreign', noted_at: day + 10.hours, latitude: 52.5, longitude: 13.4)

    expect(assemble).to eq([])
  end

  it 'keeps a note inside a privacy zone but withholds its position' do
    tag = create(:tag, :privacy_zone, user: user, privacy_radius_meters: 500)
    home = create(:place, user: user, name: 'Home', latitude: 52.444, longitude: 13.5, lonlat: 'POINT(13.5 52.444)')
    create(:tagging, tag: tag, taggable: home)
    create(:note, user: user, body: 'At home', noted_at: day + 10.hours, latitude: 52.444, longitude: 13.5)

    note = assemble(masker: Maps::PrivacyZoneMasker.new(user)).first[:notes].sole

    expect(note).to include(body: 'At home', latitude: nil, longitude: nil)
  end

  it 'shows notes older than the Lite data window on a day with nothing else' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user.update!(plan: :lite)
    old_day = 3.years.ago.beginning_of_day
    create(:visit, user: user, started_at: old_day + 7.hours, ended_at: old_day + 8.hours, duration: 60)
    create(:note, user: user, body: 'Long ago', noted_at: old_day + 9.hours, latitude: 52.5, longitude: 13.4)

    result = assemble(from: old_day, to: old_day + 1.day).sole

    expect(result[:notes].pluck(:body)).to eq(['Long ago'])
    expect(result[:entries]).to eq([])
    expect(result[:summary][:facts]).to be_nil
  end

  describe 'facts line' do
    it 'names the places of the day in order with the distance travelled' do
      create_visit('Home', 7.hours, 8.hours)
      create(:track, user: user, start_at: day + 8.hours, end_at: day + 8.hours + 30.minutes,
                     distance: 8500, duration: 1800, dominant_mode: :cycling)
      create_visit('Office', 8.hours + 30.minutes, 17.hours)
      create_visit('Home', 18.hours, 23.hours)

      expect(assemble.first[:summary][:facts]).to eq('Home → Office → Home · 8.5 km')
    end

    it 'does not repeat a place visited twice in a row and skips declined visits' do
      create_visit('Home', 7.hours, 8.hours)
      create_visit('Home', 9.hours, 10.hours)
      create_visit('Bar', 20.hours, 21.hours).update!(status: :declined)

      expect(assemble.first[:summary][:facts]).to eq('Home')
    end
  end
end
