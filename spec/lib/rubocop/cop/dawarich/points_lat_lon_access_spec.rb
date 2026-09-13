# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../../lib/rubocop/cop/dawarich/points_lat_lon_access'

RSpec.describe RuboCop::Cop::Dawarich::PointsLatLonAccess, :config do
  describe 'symbol args in AR query methods' do
    it 'flags pluck(:latitude, :longitude)' do
      expect_offense(<<~RUBY)
        visit.points.pluck(:latitude, :longitude)
                           ^^^^^^^^^ Avoid querying `:latitude`/`:longitude` on the `points` table — those columns are nil since the `lonlat` migration. Read `Point#lat`/`Point#lon` or use `ST_Y(lonlat::geometry)`/`ST_X(lonlat::geometry)`. Disable locally if querying `Place` or `Area`.
                                      ^^^^^^^^^^ Avoid querying `:latitude`/`:longitude` on the `points` table — those columns are nil since the `lonlat` migration. Read `Point#lat`/`Point#lon` or use `ST_Y(lonlat::geometry)`/`ST_X(lonlat::geometry)`. Disable locally if querying `Place` or `Area`.
      RUBY
    end

    it 'flags pluck on a renamed local' do
      expect_offense(<<~RUBY)
        sampled.pluck(:latitude, :longitude, :timestamp)
                      ^^^^^^^^^ Avoid querying `:latitude`/`:longitude` on the `points` table — those columns are nil since the `lonlat` migration. Read `Point#lat`/`Point#lon` or use `ST_Y(lonlat::geometry)`/`ST_X(lonlat::geometry)`. Disable locally if querying `Place` or `Area`.
                                 ^^^^^^^^^^ Avoid querying `:latitude`/`:longitude` on the `points` table — those columns are nil since the `lonlat` migration. Read `Point#lat`/`Point#lon` or use `ST_Y(lonlat::geometry)`/`ST_X(lonlat::geometry)`. Disable locally if querying `Place` or `Area`.
      RUBY
    end

    it 'flags select(:latitude)' do
      expect_offense(<<~RUBY)
        relation.select(:latitude)
                        ^^^^^^^^^ Avoid querying `:latitude`/`:longitude` on the `points` table — those columns are nil since the `lonlat` migration. Read `Point#lat`/`Point#lon` or use `ST_Y(lonlat::geometry)`/`ST_X(lonlat::geometry)`. Disable locally if querying `Place` or `Area`.
      RUBY
    end

    it 'flags where(latitude: ...) hash form' do
      expect_offense(<<~RUBY)
        relation.where(latitude: 0)
                       ^^^^^^^^^^^ Avoid querying `:latitude`/`:longitude` on the `points` table — those columns are nil since the `lonlat` migration. Read `Point#lat`/`Point#lon` or use `ST_Y(lonlat::geometry)`/`ST_X(lonlat::geometry)`. Disable locally if querying `Place` or `Area`.
      RUBY
    end

    it 'flags order(:longitude)' do
      expect_offense(<<~RUBY)
        relation.order(:longitude)
                       ^^^^^^^^^^ Avoid querying `:latitude`/`:longitude` on the `points` table — those columns are nil since the `lonlat` migration. Read `Point#lat`/`Point#lon` or use `ST_Y(lonlat::geometry)`/`ST_X(lonlat::geometry)`. Disable locally if querying `Place` or `Area`.
      RUBY
    end
  end

  describe 'method-call reads on Point instances' do
    it 'flags point.latitude / point.longitude (lvar receiver named `point`)' do
      expect_offense(<<~RUBY)
        point.latitude
        ^^^^^^^^^^^^^^ `Point#latitude`/`Point#longitude` read legacy nil columns. Use `Point#lat`/`Point#lon`.
        point.longitude
        ^^^^^^^^^^^^^^^ `Point#latitude`/`Point#longitude` read legacy nil columns. Use `Point#lat`/`Point#lon`.
      RUBY
    end

    it 'flags reads inside a block iterating a points relation' do
      expect_offense(<<~RUBY)
        user.points.map { |p| [p.latitude, p.longitude] }
                               ^^^^^^^^^^ `Point#latitude`/`Point#longitude` read legacy nil columns. Use `Point#lat`/`Point#lon`.
                                           ^^^^^^^^^^^ `Point#latitude`/`Point#longitude` read legacy nil columns. Use `Point#lat`/`Point#lon`.
      RUBY
    end
  end

  describe 'legitimate cases (no offense)' do
    it 'allows method-arg names called latitude / longitude' do
      expect_no_offenses(<<~RUBY)
        def find_points_near(user, latitude, longitude, radius)
          [latitude, longitude, radius]
        end
      RUBY
    end

    it 'allows controller params permits' do
      expect_no_offenses(<<~RUBY)
        params.require(:point).permit(:latitude, :longitude)
      RUBY
    end

    it 'allows reads on `place` / `area` / other lvars' do
      expect_no_offenses(<<~RUBY)
        place.latitude
        area.longitude
        visit.area&.latitude
        result.latitude
      RUBY
    end

    it 'allows Point#lat / Point#lon' do
      expect_no_offenses(<<~RUBY)
        point.lat
        point.lon
        user.points.map { |p| [p.lat, p.lon] }
      RUBY
    end

    it 'does not parse SQL string literals' do
      expect_no_offenses(<<~RUBY)
        Point.connection.select_all("SELECT latitude, longitude FROM points LIMIT 1")
      RUBY
    end

    it 'allows hash keys outside `where(...)`' do
      expect_no_offenses(<<~RUBY)
        broadcast(latitude: lat, longitude: lon)
      RUBY
    end
  end
end
