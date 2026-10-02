defmodule Dawarich.MapApi.PointRecordTest do
  use ExUnit.Case, async: true

  alias Dawarich.MapApi.PointRecord

  @migration_order ~w(id latitude longitude timestamp created_at updated_at user_id import_id altitude velocity battery ping accuracy tracker_id topic raw_data trigger bssid ssid connection vertical_accuracy mode inrids in_regions city country geodata reverse_geocoded_at course course_accuracy external_track_id lonlat country_id visit_id battery_status motion_data raw_data_archived raw_data_archive_id lock_version country_name track_id anomaly altitude_decimal source_id)
  @serialized ~w(id timestamp altitude velocity battery ping accuracy tracker_id topic trigger bssid ssid connection vertical_accuracy mode inrids in_regions city country geodata reverse_geocoded_at course course_accuracy external_track_id lonlat battery_status motion_data raw_data_archived raw_data_archive_id country_name track_id anomaly altitude_decimal)

  test "a point serializes its keys in the database's column order, legacy coordinates ignored" do
    assert {:ok, columns} = PointRecord.columns(@migration_order)
    assert columns == @serialized

    row = %{"id" => 1, "longitude" => 13.5, "latitude" => 52.25, "revision" => 3}
    {:object, pairs} = PointRecord.term(row, columns, false)

    assert Enum.map(pairs, &elem(&1, 0)) == @serialized ++ ~w(latitude longitude revision)
    assert List.keyfind(pairs, "lonlat", 0) == {"lonlat", "POINT (13.5 52.25)"}
  end

  test "a points table outside the known columns hands the request to Rails" do
    assert {:replay, _} = PointRecord.columns(@migration_order ++ ["extra"])
    assert {:replay, _} = PointRecord.columns(@migration_order -- ["mode"])
  end
end
