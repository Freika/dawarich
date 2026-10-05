defmodule Dawarich.Mail.Digests.DataTest do
  use Dawarich.JobsCase

  alias Dawarich.{DigestFixtures, ScratchRepo}
  alias Dawarich.Mail.Digests.Data

  @path Path.expand("../../../fixtures/mail/residual/digest_content.json", __DIR__)
  @now "2026-10-04T12:00:00Z"

  test "digest mail data preserves source conversions periods and all yearly stats" do
    rows = @path |> File.read!() |> Jason.decode!() |> Map.fetch!("cases")
    cases = Enum.filter(rows, &is_nil(&1["error"]))
    assert length(cases) == 20

    for row <- cases do
      rows("TRUNCATE public.digests, public.stats, public.users CASCADE")
      load(row)

      result =
        Data.fetch(ScratchRepo, row["user_id"], row["period"], 2024, row["digest"]["month"])

      assert result.user.email == row["email"]
      assert result.user.settings == row["settings"]
      assert result.digest["id"] == row["digest"]["id"]
      assert result.digest["year"] == 2024
      assert result.digest["period_type"] == row["period"]

      if row["period"] == "yearly" and not String.ends_with?(row["id"], ["_empty", "_nil_json"]) do
        values = result.projection["daily_values"]

        assert values["2024-12-31"] ==
                 Data.convert_distance(5000, result.projection["distance_unit"])

        assert values["2024-01-01"] ==
                 Data.convert_distance(500, result.projection["distance_unit"]),
               "foreign user changed January distance"

        refute Map.has_key?(values, "2023-01-01")

        refute Enum.any?(values, fn {_date, value} ->
                 value == Data.convert_distance(880_000, result.projection["distance_unit"])
               end)
      end

      assert result.projection == row["projection"], row["id"]

      assert Data.fetch(ScratchRepo, 469_999, row["period"], 2024, row["digest"]["month"]) == nil

      assert Data.fetch(ScratchRepo, row["user_id"], row["period"], 2000, row["digest"]["month"]) ==
               nil
    end
  end

  defp load(row) do
    users = Enum.uniq([row["user_id"] | Enum.map(row["stats"], & &1["user_id"])])

    for id <- users do
      user = %{
        "id" => id,
        "email" => if(id == row["user_id"], do: row["email"], else: "foreign-digest@test"),
        "settings" => row["settings"],
        "created_at" => @now,
        "updated_at" => @now
      }

      DigestFixtures.row!(ScratchRepo, "users", user)
    end

    digest =
      row["digest"]
      |> Map.put("period_type", if(row["period"] == "monthly", do: 0, else: 1))
      |> Map.merge(%{"created_at" => @now, "updated_at" => @now})

    DigestFixtures.row!(ScratchRepo, "digests", digest)

    for stat <- row["stats"] do
      stat = Map.merge(stat, %{"distance" => 0, "created_at" => @now, "updated_at" => @now})
      DigestFixtures.row!(ScratchRepo, "stats", stat)
    end
  end
end
