defmodule DawarichWeb.InsightsDetailsParityTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Insights.{Details, Fragments}
  alias Dawarich.Test.{InsightsSeeds, ParityHTML, RailsUser}

  @dir Path.expand("../fixtures/insights", __DIR__)
  @corpus @dir |> Path.join("details-corpus.json") |> File.read!() |> Jason.decode!()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    InsightsSeeds.start_cache!()
    InsightsSeeds.corpus!(@corpus)

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    %{port: port, upstream: upstream}
  end

  test "fragments are keyed with the template digest Rails renders insights/details with" do
    data = %{selected: 2024, max_stat_updated: nil, unit: "km"}
    key = Fragments.key(%{id: 1, settings: %{}}, "en", data, "travel_patterns")
    assert String.starts_with?(key, "views/" <> @corpus["template_digest"] <> "/")
  end

  @parts ~w(year_comparison activity_breakdown location_clusters monthly_digest travel_patterns movement_wellness)

  test "warm nil stale and cold details preserve the source corpus values and order", ctx do
    for {state, order} <- [
          {"fresh", ~w(walking stationary flying)},
          {"persisted", ~w(flying walking stationary)}
        ] do
      values = %{
        "walking" => %{"duration" => 600, "percentage" => 14},
        "stationary" => %{"duration" => 1800, "percentage" => 43},
        "flying" => %{"duration" => 1800, "percentage" => 43}
      }

      patterns = %Jason.OrderedObject{
        values: [
          {"activity_breakdown", %Jason.OrderedObject{values: Enum.map(order, &{&1, values[&1]})}}
        ]
      }

      data =
        Dawarich.RailsCache.JsonOrder.pattern_pairs(%{
          "_rails_json" => %{"travel_patterns" => Jason.encode!(patterns)}
        })
        |> Map.put(:activity, values)

      actual =
        render_component(&DawarichWeb.InsightsDetails.Activity.render/1, %{
          locale: "en",
          data: data
        })

      expected = File.read!(Path.join(@dir, "activity-#{state}.html"))
      assert ParityHTML.normalize(actual) == ParityHTML.normalize(expected)
    end

    before = Dawarich.Repo.query!("SELECT id,updated_at FROM digests ORDER BY id", []).rows

    for request <- @corpus["requests"] do
      key = Enum.find(@corpus["cache"], &String.contains?(&1["key"], "/#{request["user_id"]}/"))
      cookie = "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(request["user_id"]))
      expected_bytes = File.read!(Path.join(@dir, request["fixture"]))
      expected = ParityHTML.normalize(expected_bytes)

      for state <- [:warm, :stale, nil, :cold] do
        for fragment <- request["fragment_keys"],
            do: Dawarich.Redis.cache_command(["DEL", fragment])

        InsightsSeeds.cache!(key["key"], Base.decode64!(key["wire"]))

        if state == :stale,
          do:
            Dawarich.Repo.query!(
              "UPDATE digests SET distance=888 WHERE user_id=$1 AND period_type=1",
              [request["user_id"]]
            )

        if state == nil,
          do:
            InsightsSeeds.cache!(
              key["key"],
              Dawarich.RailsCache.Wire.encode_boolean(nil, expires_at: nil)
            )

        if state == :cold, do: Dawarich.Redis.cache_command(["DEL", key["key"]])
        client = connect(ctx.port)

        send_raw(
          client,
          "GET #{request["path"]} HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\nTurbo-Frame: insights_details\r\n\r\n"
        )

        if state == :cold do
          upstream = accept(ctx.upstream)
          {head, _} = read_head(upstream)
          assert request_line(head) == "GET #{request["path"]} HTTP/1.1"

          reply(
            upstream,
            "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(expected_bytes)}\r\n\r\n#{expected_bytes}"
          )
        end

        assert {200, _, body} = read_response(client)

        if state == nil do
          locale =
            URI.parse(request["path"]).query
            |> to_string()
            |> URI.decode_query()
            |> Map.get("locale", "en")

          {:ok, message} =
            Dawarich.I18n.t(
              locale,
              "insights.activity_breakdown.no_activity_data_available_for_this_period"
            )

          assert body |> LazyHTML.from_document() |> LazyHTML.text() =~ message
          assert body =~ ~s(<turbo-frame id="insights_details">)
        else
          assert ParityHTML.fragment(body, "turbo-frame#insights_details") == expected
        end
      end
    end

    assert Dawarich.Repo.query!("SELECT id,updated_at FROM digests ORDER BY id", []).rows ==
             before
  end

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
