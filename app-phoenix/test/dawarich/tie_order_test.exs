defmodule Dawarich.TieOrderTest do
  use Dawarich.IngestCase, async: true

  alias Dawarich.{Digests.LocationTime, Insights.Details, Locations, RailsTime, Residency}
  alias Dawarich.Test.{FrameSeeds, StatsSeeds}

  @now ~U[2026-10-03 10:00:00Z]

  setup do
    user = FrameSeeds.user!(91963, %{"timezone" => "UTC"})
    StatsSeeds.stat!(user.id, %{year: 2026, month: 1, distance: 1000})
    %{user: user}
  end

  defp plans(fun) do
    for {seq, index} <- [{"on", "off"}, {"off", "on"}] do
      Repo.query!("SET LOCAL enable_seqscan = #{seq}")
      Repo.query!("SET LOCAL enable_indexscan = #{index}")
      Repo.query!("SET LOCAL enable_indexonlyscan = off")
      Repo.query!("SET LOCAL enable_bitmapscan = off")

      for hash <- ["on", "off"] do
        Repo.query!("SET LOCAL enable_hashagg = #{hash}")
        Repo.query!("SET LOCAL enable_sort = #{if hash == "on", do: "off", else: "on"}")
        fun.()
      end
    end
  end

  test "top visited exact ties use name order before applying the limit", %{user: user} do
    names = ~w(Zeta Delta Gamma Alpha Beta Epsilon)

    for {name, index} <- Enum.with_index(names) do
      FrameSeeds.visit!(user.id, 919_630 + index, %{
        name: name,
        started_at: ~N[2026-01-02 10:00:00],
        ended_at: ~N[2026-01-02 10:01:00],
        duration: 1,
        status: 1
      })
    end

    plans(fn ->
      data = Details.load(user, %{"year" => "2026"}, now: @now, self_hosted: true)
      assert Enum.map(data.top_visits, & &1.name) == ~w(Alpha Beta Delta Epsilon Gamma)
    end)
  end

  test "country count and duration ties use country order", %{user: user} do
    for {country, index} <- Enum.with_index(~w(Germany France Spain Italy Austria Portugal)) do
      FrameSeeds.point!(user.id, 919_630 + index, DateTime.to_unix(@now), country_name: country)

      Repo.query!(
        "UPDATE points SET lonlat=ST_SetSRID(ST_MakePoint(12.3731,$1),4326)::geography WHERE id=$2",
        [51.3398 + index * 0.0001, 919_630 + index]
      )
    end

    context = %{user_id: user.id}
    period = %{month: 10, zone: "UTC", location_first: 0, last: DateTime.to_unix(@now)}

    plans(fn ->
      {:ok, {:object, fields}} =
        Residency.term(user.id, {2026, 0, DateTime.to_unix(@now)}, :source)

      fields = Map.new(fields)
      assert fields["daily_countries"] == {:object, [{"2026-10-03", "Austria"}]}

      assert Enum.map(fields["countries"], fn {:object, country} ->
               Map.new(country)["country_name"]
             end) == ~w(Austria France Germany Italy Portugal Spain)

      result = LocationTime.calculate(Repo, context, period, [])

      assert result["countries"] ==
               Enum.map(
                 ~w(Austria France Germany Italy Portugal Spain),
                 &%{"name" => &1, "minutes" => 240}
               )
    end)
  end

  test "location equal timestamps and accuracy keep point ID order", %{user: user} do
    for {id, lat} <- [{919_631, 51.3398}, {919_630, 51.3397}] do
      FrameSeeds.point!(user.id, id, DateTime.to_unix(@now))

      Repo.query!(
        "UPDATE points SET lonlat=ST_SetSRID(ST_MakePoint(12.3731,$1),4326)::geography,accuracy=10 WHERE id=$2",
        [lat, id]
      )
    end

    search = %{
      lat: 51.3397,
      lon: 12.3731,
      radius: 500,
      date_from: nil,
      date_to: nil,
      limit: 50,
      name: "Cafe",
      address: ""
    }

    plans(fn ->
      rows = RailsTime.with_zone("UTC", fn -> Locations.rows(user.id, search) end)
      assert Enum.map(rows, &Enum.at(&1, 1)) == [51.3397, 51.3398]
      {:ok, {:object, fields}} = Dawarich.Locations.Closure.term(search, rows)
      [{:object, location}] = Map.new(fields)["locations"]
      [{:object, visit}] = Map.new(location)["visits"]
      assert Map.new(visit)["coordinates"] == [51.3397, 12.3731]
    end)
  end
end
