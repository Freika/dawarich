# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'City collectible exploration' do
  let(:user) { create(:user) }
  let(:dataset) { Exploration::Dataset.create!(version: 'city-test', completed_at: Time.current) }
  let(:connection) { ApplicationRecord.connection }

  before do
    allow(Exploration::Geography).to receive(:current).and_return(dataset)
    allow(Exploration::Geography).to receive(:install!).and_return(dataset)
    connection.execute(<<~SQL)
      INSERT INTO exploration_territories(dataset_id,code,name,kind,timezone,boundary,land,land_area)
      SELECT #{dataset.id},'city_test','Test City','city','Europe/Berlin',g,g,ST_Area(g::geography)
      FROM (SELECT ST_Multi(ST_MakeEnvelope(13.30,52.49,13.40,52.55,4326)) g) s
    SQL
  end

  def add_point(timestamp:, lon: 13.34999, lat: 52.514)
    Point.insert_all!([{ user_id: user.id, timestamp: timestamp, lonlat: "POINT(#{lon} #{lat})",
                        created_at: Time.current, updated_at: Time.current }])
  end

  def calculate
    Achievements::CollectionChecker.new(user, notify: false).call
    user.achievement_collectibles.find_by!(series: 'city')
  end

  it 'uses exact clipped land area from the shared published snapshot, independently of recording frequency' do
    user.achievement_city_selections.create!(territory_code: 'city_test')
    add_point(timestamp: 100)
    card = calculate
    source = Exploration::CountryTotal.find_by!(snapshot_id: card.data['snapshot_id'])
    expect(card.data['opened_area']).to eq(source.opened_area)
    expect(card.data['progress']).to be > 0
    original = card.data['progress']
    add_point(timestamp: 200)
    expect(calculate.data['progress']).to eq(original)
    expect(card.data['levels']).to eq({})
  end

  it 'closes cells on removal and changes earliest evidence on historical imports' do
    user.achievement_city_selections.create!(territory_code: 'city_test')
    add_point(timestamp: 200)
    calculate
    add_point(timestamp: 100)
    card = calculate
    expect(Exploration::Opening.find_by!(snapshot_id: card.data['snapshot_id']).first_timestamp).to eq(100)
    user.points.delete_all
    expect(calculate.data['progress']).to eq(0)
  end

  it 'does not award a city level from future-only observations' do
    connection.execute(<<~SQL)
      UPDATE exploration_territories SET
        boundary = ST_Multi(ST_MakeEnvelope(13.3499,52.5139,13.3501,52.5141,4326)),
        land = ST_Multi(ST_MakeEnvelope(13.3499,52.5139,13.3501,52.5141,4326))
      WHERE dataset_id = #{dataset.id};
      UPDATE exploration_territories SET land_area = ST_Area(land::geography) WHERE dataset_id = #{dataset.id};
    SQL
    user.achievement_city_selections.create!(territory_code: 'city_test')
    add_point(timestamp: 1.day.from_now.to_i)

    card = calculate
    expect(card.level).to eq(0)
    expect(card.data['progress']).to eq(0)
    expect(card.data['levels']).to eq({})
    expect(card.events.where(kind: 'earned')).to be_empty
  end

  it 'clips water and border-cell fragments rather than counting equal cells' do
    city = Exploration::Territory.find_by!(code: 'city_test')
    connection.execute(<<~SQL)
      UPDATE exploration_territories SET land=ST_Multi(ST_Difference(land,
        ST_MakeEnvelope(13.3498,52.5138,13.3502,52.5142,4326))) WHERE id=#{city.id};
      UPDATE exploration_territories SET land_area=ST_Area(land::geography) WHERE id=#{city.id};
    SQL
    user.achievement_city_selections.create!(territory_code: 'city_test')
    add_point(timestamp: 100)
    card = calculate
    cell_area = connection.select_value('SELECT ST_Area(geom::geography) FROM exploration_cells LIMIT 1').to_f
    expect(card.data['opened_area']).to be < cell_area
    expect(Achievements::CityArtwork.new(card).call[:unvisited_path]).to be_present
  end

  it 'shares a generic silhouette by default and masks both mosaic and progress when opted in' do
    selection = user.achievement_city_selections.create!(territory_code: 'city_test')
    add_point(timestamp: 100)
    card = calculate
    public_card = Achievements::CollectiblePresenter.new(card, public: true)
    expect(public_card.card_attributes[:silhouette][:unvisited_path]).to be_nil
    expect(public_card.metric_label).to eq('City exploration · 0% level')
    selection.update!(share_mosaic: true)
    calculate

    place = create(:place, user: user, latitude: 52.514, longitude: 13.34999)
    place.tags << create(:tag, user: user, privacy_radius_meters: 500)
    card.reload
    public_card = Achievements::CollectiblePresenter.new(card, public: true)
    expect(public_card.card.data['progress']).to eq(0)
    expect(public_card.card.level).to eq(0)
    expect(public_card.card_attributes[:silhouette][:unvisited_path]).to be_present
  end
end
