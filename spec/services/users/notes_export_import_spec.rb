# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'notes export/import', type: :service do
  let(:source) { create(:user) }
  let(:target) { create(:user) }
  let(:archive_path) { Rails.root.join("tmp/notes_export_#{SecureRandom.hex(4)}.zip") }

  let(:trip) do
    create(:trip, user: source, name: 'Lisbon', started_at: Time.utc(2025, 5, 1, 8), ended_at: Time.utc(2025, 5, 4, 20))
  end
  let(:place) { create(:place, user: source, name: 'Cafe', latitude: 38.71, longitude: -9.14) }
  let(:visit) do
    create(:visit, user: source, place: place, name: 'Cafe visit',
                   started_at: Time.utc(2025, 5, 2, 9), ended_at: Time.utc(2025, 5, 2, 10))
  end

  after { FileUtils.rm_f(archive_path) }

  def round_trip
    export = Users::ExportData.new(source).export
    File.binwrite(archive_path, export.file.download)
    Users::ImportData.new(target, archive_path).import
  end

  before do
    create(:note, user: source, attachable: trip, body: 'Day two', noted_at: Time.utc(2025, 5, 2, 12))
    create(:note, user: source, attachable: place, body: 'Best pastel de nata', noted_at: Time.utc(2025, 5, 2, 9, 30))
    create(:note, user: source, attachable: visit, body: 'Met Ana', noted_at: Time.utc(2025, 5, 2, 9, 45))
    create(:note, user: source, body: 'Rain started here', noted_at: Time.utc(2025, 5, 3, 15, 20),
                  latitude: 38.7223, longitude: -9.1393)
  end

  it 'restores standalone notes with their place and moment' do
    stats = round_trip

    note = target.notes.standalone.sole
    expect(note.body).to eq('Rain started here')
    expect(note.noted_at).to eq(Time.utc(2025, 5, 3, 15, 20))
    expect(note.latitude).to be_within(0.00001).of(38.7223)
    expect(note.longitude).to be_within(0.00001).of(-9.1393)
    expect(stats[:notes_created]).to eq(4)
  end

  it 're-attaches notes to the imported trip, place and visit' do
    round_trip

    expect(target.trips.find_by(name: 'Lisbon').notes.sole.body).to eq('Day two')
    expect(target.places.find_by(name: 'Cafe').notes.sole.body).to eq('Best pastel de nata')
    expect(target.visits.find_by(name: 'Cafe visit').notes.sole.body).to eq('Met Ana')
  end

  it 'does not duplicate notes when the same archive is imported twice' do
    round_trip
    second = Users::ImportData.new(target, archive_path).import

    expect(target.notes.count).to eq(4)
    expect(second[:notes_created]).to eq(0)
  end

  it 'keeps a note as standalone when its attachable is not in the archive' do
    data = [{ 'body' => 'Orphan', 'noted_at' => '2025-05-02T12:00:00.000Z', 'attachable_type' => 'Trip',
              'attachable_reference' => { 'name' => 'Gone', 'started_at' => '2020-01-01T00:00:00.000Z',
                                          'ended_at' => '2020-01-02T00:00:00.000Z' } }]

    expect(Users::ImportData::Notes.new(target, data).call).to eq(1)
    expect(target.notes.standalone.sole.body).to eq('Orphan')
  end
end
