defmodule DawarichWeb.InsightsDetailsParityTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP

  alias Dawarich.Insights.{Details, Fragments}
  alias Dawarich.Test.{InsightsSeeds, ParityHTML, RailsUser}

  @dir Path.expand("../fixtures/insights", __DIR__)
  @corpus @dir |> Path.join("details-corpus.json") |> File.read!() |> Jason.decode!()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, listen().port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    InsightsSeeds.start_cache!()
    InsightsSeeds.corpus!(@corpus)

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    %{port: port}
  end

  test "fragments are keyed with the template digest Rails renders insights/details with" do
    data = %{selected: 2024, max_stat_updated: nil, unit: "km"}
    key = Fragments.key(%{id: 1, settings: %{}}, "en", data, "travel_patterns")
    assert String.starts_with?(key, "views/" <> @corpus["template_digest"] <> "/")
  end

  @parts ~w(year_comparison activity_breakdown location_clusters monthly_digest travel_patterns movement_wellness)

  for request <- @corpus["requests"] do
    @request request
    test "Phoenix keys the fragments of #{request["path"]} exactly as Rails wrote them" do
      %{"settings" => settings, "plan" => plan} =
        Enum.find(@corpus["users"], &(&1["id"] == @request["user_id"]))

      user = %{id: @request["user_id"], settings: settings, plan: plan}
      query = @request["path"] |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      data = Details.load(user, query, self_hosted: false)
      keys = for name <- @parts, do: Fragments.key(user, query["locale"] || "en", data, name)
      assert Enum.sort(keys) == Enum.sort(@request["fragment_keys"])
    end

    test "Phoenix answers #{request["path"]} as Rails renders #{request["fixture"]}", ctx do
      expected = @dir |> Path.join(@request["fixture"]) |> File.read!() |> ParityHTML.normalize()
      cookie = "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(@request["user_id"]))

      for pass <- [:cold_fragments, :warm_fragments] do
        client = connect(ctx.port)

        send_raw(
          client,
          "GET #{@request["path"]} HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\nTurbo-Frame: insights_details\r\n\r\n"
        )

        assert {200, _headers, body} = read_response(client)
        actual = ParityHTML.fragment(body, "turbo-frame#insights_details")

        assert actual == expected,
               "#{pass}: #{inspect(first_difference(actual, expected), limit: 12)}"
      end
    end
  end

  defp first_difference(a, a), do: nil

  defp first_difference(a, b) when is_list(a) and is_list(b) and length(a) == length(b),
    do: Enum.zip(a, b) |> Enum.find_value(fn {a, b} -> first_difference(a, b) end)

  defp first_difference(a, b) when is_tuple(a) and is_tuple(b) and tuple_size(a) == tuple_size(b),
    do: first_difference(Tuple.to_list(a), Tuple.to_list(b))

  defp first_difference(a, b), do: {a, b}
end
