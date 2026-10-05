defmodule Dawarich.Imports.GpxPointTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Imports.GpxPoint
  @oracle Path.expand("../../fixtures/gpx/rails_preparation_oracle.json", __DIR__)
  @cases @oracle
         |> File.read!()
         |> Jason.decode!()
         |> Map.fetch!("point_cases")
         |> Enum.group_by(& &1["name"])
  @import %{id: 42, user_id: 9, name: "oracle.gpx"}
  @ctx %{
    now: ~U[2026-01-15 23:30:00Z],
    zone: "Europe/Berlin",
    altitude_decimal?: true,
    repo: Dawarich.Repo
  }

  for {name, examples} <- @cases do
    @examples examples
    test "actual Rails GPX preparation: #{name}" do
      for example <- @examples do
        if example["error"] do
          assert_raise ArgumentError, fn ->
            GpxPoint.prepare(example["point"], example["tracker_id"], @import, @ctx)
          end
        else
          actual = GpxPoint.prepare(example["point"], example["tracker_id"], @import, @ctx)
          assert json_attributes(actual) == example["attributes"]
        end
      end
    end
  end

  test "legacy schema omits altitude_decimal while preserving integer writer altitude input" do
    raw = %{"lat" => "52.5", "lon" => "13.4", "time" => "2024-03-16T12:30:23Z", "ele" => "12.75"}
    attrs = GpxPoint.prepare(raw, "device", @import, %{@ctx | altitude_decimal?: false})
    assert attrs.altitude == 12.75
    refute Map.has_key?(attrs, :altitude_decimal)
    assert attrs.created_at == ~N[2026-01-15 23:30:00]
    assert attrs.updated_at == ~N[2026-01-15 23:30:00]
  end

  test "decimal expansion stays within the parser point budget" do
    raw = %{"lat" => "52.5", "lon" => "1e1048577", "time" => "2024-03-16T12:30:23Z"}

    assert_raise ArgumentError, ~r/coordinate expansion/, fn ->
      GpxPoint.prepare(raw, "device", @import, @ctx)
    end
  end

  defp json_attributes(nil), do: nil

  defp json_attributes(attrs) do
    Map.new(attrs, fn
      {key, %NaiveDateTime{} = stamp} ->
        {Atom.to_string(key), NaiveDateTime.to_iso8601(%{stamp | microsecond: {0, 6}}) <> "Z"}

      {key, :infinity} ->
        {Atom.to_string(key), "Infinity"}

      {key, :neg_infinity} ->
        {Atom.to_string(key), "-Infinity"}

      {key, value} ->
        {Atom.to_string(key), value}
    end)
  end
end
