defmodule DawarichWeb.Api.SharedGoldenTest do
  use Dawarich.ApiEndpointCase
  use Dawarich.JobsCase, async: false

  alias Dawarich.Test.ApiGolden
  alias Dawarich.{RailsCookies, RailsSecret}
  alias DawarichWeb.SharedLinkCookie

  @path "test/fixtures/api_shared/golden.json"
  @now (@path |> File.read!() |> Jason.decode!())["now"] |> DateTime.from_iso8601() |> elem(1)
  @moduletag api_now: @now
  @moduletag api_public_only: true
  @moduletag :capture_log
  @tables ~w(users trips tracks shared_links points tags places taggings)

  setup_all do
    %{fixture: @path |> File.read!() |> Jason.decode!()}
  end

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    :ok
  end

  for kase <- (@path |> File.read!() |> Jason.decode!())["cases"] do
    @kase kase
    @tag golden_case: String.to_atom(kase["name"])
    @tag mutation: "M-C1-shared-#{kase["name"]}"
    test "golden #{kase["name"]}", ctx do
      for {name, value} <- @kase["env"], do: System.put_env(name, value)

      for [table, seeds] <- ctx.fixture["setups"][@kase["setup"]], row <- seeds do
        assert table in @tables
        ApiGolden.insert!(table, row)
      end

      for {name, value} <- ctx.fixture["sequences"],
          do: Repo.query!("SELECT setval($1::text::regclass,$2,false)", [name, value])

      for {key, _} <- @kase["cache_after"] || %{}, do: Dawarich.Redis.cache_command(["DEL", key])

      before = after_rows()
      ApiGolden.check(cookie(@kase), ctx.port, ctx.upstream)

      assert after_rows() ==
               if(@kase["expect"] == "own", do: Map.merge(before, @kase["after"]), else: before)

      assert rows("SELECT kind,payload FROM phoenix.rails_commands") == []

      for {key, _} <- @kase["cache_after"] || %{} do
        assert Dawarich.RailsCache.get(key) == :miss
        assert Dawarich.Redis.cache_command(["TTL", key]) == {:ok, -2}
      end
    end
  end

  defp cookie(%{"runtime_cookie" => kind} = kase) do
    [[id, phrase]] = Repo.query!("SELECT id::text,magic_phrase FROM shared_links LIMIT 1").rows
    phrase = if kind == "old", do: "synthetic-phrase", else: phrase
    name = "shared_link_#{id}"

    value =
      RailsCookies.encrypt(
        SharedLinkCookie.unlock_token(id, phrase),
        name,
        RailsSecret.fetch(),
        DateTime.add(@now, 3600)
      )

    update_in(kase, ["request", "headers"], &(&1 ++ [["Cookie", "#{name}=#{value}"]]))
  end

  defp cookie(kase), do: kase

  defp after_rows do
    Repo.query!("SELECT set_config('TimeZone','UTC',true)")

    Map.new(@tables, fn table ->
      data = Repo.query!("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id").rows
      {table, Enum.map(data, fn [text] -> Jason.decode!(text) end)}
    end)
  end
end
