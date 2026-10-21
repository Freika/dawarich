defmodule DawarichWeb.Api.SharedGoldenTest do
  use Dawarich.ApiEndpointCase
  @moduletag api_golden: true
  use Dawarich.JobsCase, async: false

  alias Dawarich.Test.ApiGolden
  alias Dawarich.{RailsCookies, RailsSecret, SharedLinks}
  alias Dawarich.Photos.ProviderCache
  alias Dawarich.SharedApi.{Closure, Photos}
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

      seed!(ctx.fixture["setups"][@kase["setup"]])

      for {name, value} <- ctx.fixture["sequences"],
          do: Repo.query!("SELECT setval($1::text::regclass,$2,false)", [name, value])

      for {key, _} <- @kase["cache_after"] || %{}, do: Dawarich.Redis.cache_command(["DEL", key])

      for [[user]] <- Repo.query!("SELECT DISTINCT user_id FROM shared_links").rows,
          do: ProviderCache.invalidate(user)

      photo_provider!(@kase)
      before = after_rows()
      photo_search!(@kase)
      kase = cookie(@kase)
      kase = native(kase)

      if @kase["name"] in ~w(deleted_owner_live deleted_owner_timeline deleted_owner_track deleted_owner_trip points_timeline_invalid thumbnail_foreign thumbnail_private thumbnail_track_beyond_marker_cap thumbnail_unconfigured thumbnail_trip_beyond_marker_cap) do
        client = connect(ctx.port)
        request = kase["request"]

        send_raw(client, [
          "#{request["method"]} #{request["target"]} HTTP/1.1\r\n",
          Enum.map(request["headers"], fn [name, value] -> "#{name}: #{value}\r\n" end),
          "\r\n",
          request["body"] || ""
        ])

        assert {status, headers, body} = read_response(client)
        assert values(headers, "set-cookie") == []
        assert status == kase["response"]["status"]

        assert body ==
                 (kase["response"]["body"] || Base.decode64!(kase["response"]["body_base64"]))

        no_upstream!(ctx.upstream)
      else
        ApiGolden.check(kase, ctx.port, ctx.upstream)
      end

      if @kase["name"] in ~w(thumbnail_trip_beyond_marker_cap thumbnail_provider_failed) do
        assert_receive {:golden_photo_request, _}
      else
        refute_received {:golden_photo_request, _}
      end

      assert after_rows() ==
               if(@kase["expect"] == "own", do: Map.merge(before, @kase["after"]), else: before)

      assert rows("SELECT kind,payload FROM phoenix.rails_commands") == []

      for {key, _} <- @kase["cache_after"] || %{} do
        assert Dawarich.RailsCache.get(key) == :miss
        assert Dawarich.Redis.cache_command(["TTL", key]) == {:ok, -2}
      end
    end
  end

  test "pinned fixture batches advance each table sequence once", %{fixture: fixture} do
    kase = Enum.find(fixture["cases"], &(&1["name"] == "points_10001"))

    setup =
      for [table, seeds] <- fixture["setups"][kase["setup"]], do: [table, Enum.take(seeds, 3)]

    handler = {__MODULE__, self()}
    :ok = :telemetry.attach(handler, [:dawarich, :repo, :query], &__MODULE__.query/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    seed!(setup)

    queries = queries()
    tables = Enum.count(setup, fn [_, seeds] -> seeds != [] end)
    pinned = Enum.count(setup, fn [_, seeds] -> Enum.any?(seeds, &is_integer(&1["id"])) end)
    assert Enum.count(queries, &String.starts_with?(&1, "SELECT setval")) == pinned
    assert Enum.count(queries, &String.starts_with?(&1, "INSERT INTO")) == tables

    [_, points] = Enum.find(setup, fn [table, _] -> table == "points" end)
    [[id]] = Repo.query!("SELECT nextval(pg_get_serial_sequence('points', 'id'))").rows
    assert id > Enum.max(Enum.map(points, & &1["id"]))
    Dawarich.Test.SeedIds.advance!(Repo, "points", [1])
    assert [[next]] = Repo.query!("SELECT nextval(pg_get_serial_sequence('points', 'id'))").rows
    assert next > id
  end

  defp native(kase) do
    kase = Map.put(kase, "expect", "own")

    case kase["name"] do
      "points_timeline_invalid" ->
        put_in(kase, ["response"], %{
          "status" => 500,
          "body" => ~s({"status":500,"error":"Internal Server Error"})
        })

      name when name in ["trip_unsupported_client_header", "points_json_suffix"] ->
        update_in(
          kase,
          ["response", "headers"],
          &(Map.delete(&1, "set-cookie") |> Map.put("vary", "Accept"))
        )

      _ ->
        kase
    end
  end

  defp photo_provider!(%{"name" => "thumbnail_" <> _} = kase) do
    provider = listen()
    body = if encoded = kase["response"]["body_base64"], do: Base.decode64!(encoded), else: ""
    status = if body == "", do: 404, else: 200

    parent = self()

    photo =
      kase["request"]["target"]
      |> URI.parse()
      |> Map.fetch!(:path)
      |> String.split("/")
      |> Enum.at(-2)

    worker =
      Task.async(fn ->
        socket = accept(provider)
        {head, _} = read_head(socket)

        send(parent, {:golden_photo_request, request_line(head)})
        assert request_line(head) == "GET /api/assets/#{photo}/thumbnail?size=preview HTTP/1.1"

        reply(socket, [
          "HTTP/1.1 #{status} Result\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n",
          body
        ])

        :gen_tcp.close(socket)
      end)

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{immich_url}',to_jsonb($1::text)) WHERE id IN (SELECT user_id FROM shared_links)",
      ["http://127.0.0.1:#{provider.port}"]
    )

    on_exit(fn ->
      Process.exit(worker.pid, :kill)
      :gen_tcp.close(provider.listen)
    end)
  end

  defp photo_provider!(_), do: :ok

  defp photo_search!(%{"name" => name, "cache_after" => caches}) when is_map(caches) do
    if String.starts_with?(name, ["thumbnail_", "photos_"]) do
      [[id]] = Repo.query!("SELECT id::text FROM shared_links LIMIT 1").rows
      link = SharedLinks.active(id, @now)
      context = Photos.grant_context(link)

      if is_tuple(context.range) do
        {from, to} = context.range
        key = "photos_search/#{link.user_id}/v2/#{from}/#{to}"

        assert {:ok, _} =
                 Dawarich.Redis.cache_command([
                   "UNLINK",
                   key,
                   ProviderCache.key(link.user_id, from, to)
                 ])

        assert ProviderCache.get(key) == :miss
      end

      for {"photos_search/" <> _, %{"value" => photos}} <- caches,
          is_list(photos),
          {from, to} <- [context.range] do
        key = "photos_search/#{link.user_id}/v2/#{from}/#{to}"
        ProviderCache.put(key, photos, 60)
      end

      on_exit(fn ->
        ProviderCache.invalidate(link.user_id)
        Dawarich.Redis.cache_command(["UNLINK", Closure.photo_ids_key(link, context)])
      end)
    end
  end

  defp photo_search!(_), do: :ok

  def query(_event, _measurements, %{query: query}, parent), do: send(parent, {:query, query})

  defp queries do
    receive do
      {:query, query} -> [query | queries()]
    after
      0 -> []
    end
  end

  defp seed!(setup) do
    for [table, seeds] <- setup, seeds != [] do
      assert table in @tables
      ApiGolden.insert!(table, seeds)
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
