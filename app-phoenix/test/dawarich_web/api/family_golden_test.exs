defmodule DawarichWeb.Api.FamilyGoldenTest do
  use Dawarich.ApiEndpointCase
  @moduletag api_golden: true

  alias Dawarich.Test.ApiGolden

  @golden "test/rails_fixtures/api_family/golden.json" |> File.read!() |> Jason.decode!()
  @tables ~w(users families family_memberships point_sources points)
  @moduletag api_now: ~U[2037-01-15 10:30:00Z]

  setup do
    if zone = @golden["time_zone"], do: System.put_env("TIME_ZONE", zone)
    previous = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", Dawarich.Test.FamilyGoldenResponse.secret())

    on_exit(fn ->
      if previous,
        do: System.put_env("JWT_SECRET_KEY", previous),
        else: System.delete_env("JWT_SECRET_KEY")
    end)

    :ok
  end

  for kase <- @golden["cases"] do
    @kase kase
    test "golden #{kase["name"]}", %{port: port, upstream: puma} do
      Enum.each(@kase["env"], fn {name, value} -> System.put_env(name, value) end)

      for [table, rows] <- @golden["setups"][@kase["setup"]], row <- rows do
        true = table in @tables
        ApiGolden.insert!(table, row)
      end

      before = digests()

      kase =
        if @kase["name"] == "replay_member_settings_null" do
          assert @kase["response"]["status"] == 500
          source = Enum.find(@golden["cases"], &(&1["name"] == "locations_member_disabled"))
          Map.put(@kase, "response", source["response"])
        else
          @kase
        end

      Dawarich.Test.FamilyGoldenResponse.check(kase, port, puma)
      assert digests() == before
      assert after_rows() == @kase["after"]
    end
  end

  defp after_rows do
    Map.new(@tables, fn table ->
      rows = Repo.query!("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id").rows

      {table,
       Enum.map(rows, fn [json] -> Jason.decode!(json) |> Map.reject(&is_nil(elem(&1, 1))) end)}
    end)
  end

  defp digests do
    Repo.query!("SELECT set_config('TimeZone', 'UTC', true)")

    for table <- @tables do
      Repo.query!(
        "SELECT md5(coalesce(string_agg(t::text, '|' ORDER BY id), '')) FROM #{table} t"
      ).rows
    end
  end
end
