defmodule Dawarich.Digests.ReadConsumersTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.{DigestFixtures, Digests, Jsonb}
  alias Dawarich.Digests.{Api, Calculation}
  alias Dawarich.Insights.Details.Digests, as: Details

  test "existing digest readers consume generated rows without changing route ownership" do
    yearly = DigestFixtures.case!("berlin_yearly")
    monthly = DigestFixtures.case!("berlin_monthly")
    DigestFixtures.load!(Repo, yearly)
    opts = DigestFixtures.options(yearly)
    assert {:ok, year_id} = Calculation.yearly(Repo, 14101, 2025, opts)

    monthly_opts = Keyword.put(DigestFixtures.options(monthly), :uuid, Ecto.UUID.generate())
    assert {:ok, month_id} = Calculation.monthly(Repo, 14101, 2025, 3, monthly_opts)
    assert month_id != year_id
    expected = hd(yearly["expected"]["rows"])
    context = %{today: ~D[2026-10-03], cutoff: nil}
    assert %{digests: [index], available_years: [2024]} = Digests.index(14101, context)
    assert index.year == 2025
    assert index.distance == expected["distance"]

    digest = Digests.get(14101, 2025)
    assert digest.distance == expected["distance"]

    assert digest.monthly_distances ==
             Enum.sort_by(expected["monthly_distances"], fn {month, _} ->
               String.to_integer(month)
             end)

    assert digest.first_time_cities == expected["first_time_visits"]["cities"]
    assert digest.total_distance_all_time == 39500

    assert {:ok, api} = Api.show(14101, 2025)
    assert api.distance == expected["distance"]
    assert Jsonb.get(api.all_time, "total_distance") == "39500"
    assert {:ok, {:object, fields}} = Api.detail(api, "km")
    assert Map.new(fields)["year"] == 2025
    assert {:ok, {:object, _}} = Api.index(14101, opts[:now])

    result = Repo.query!("SELECT year, month, updated_at FROM public.stats WHERE user_id = 14101")
    stats = Enum.map(result.rows, &(result.columns |> Enum.zip(&1) |> Map.new()))
    assert {month, false} = Details.monthly(14101, 2025, 3, [3], stats)
    assert month["id"] == month_id
    assert month["distance"] == hd(monthly["expected"]["rows"])["distance"]
    assert {year, true} = Details.yearly(14101, 2025, stats)
    assert year["id"] == year_id
    assert year["travel_patterns"] == expected["travel_patterns"]

    assert %{route: "/digests/:year"} =
             Phoenix.Router.route_info(DawarichWeb.Router, "GET", "/digests/2025", "localhost")

    assert Phoenix.Router.route_info(DawarichWeb.Router, "POST", "/digests", "localhost") ==
             :error
  end
end
