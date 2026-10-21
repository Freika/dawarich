defmodule DawarichWeb.Api.IngestGoldenTest do
  use Dawarich.IngestCase, async: false
  import Dawarich.Test.RawHTTP

  @golden "test/fixtures/ingest/golden.json" |> File.read!() |> Jason.decode!()
  @capture "test/rails_captures/ingest.json" |> File.read!() |> Jason.decode!()
  @captured Map.new(@capture["cases"], &{&1["name"], &1})
  @golden Map.update!(
            @golden,
            "cases",
            &Enum.map(&1, fn kase -> @captured[kase["name"]] || kase end)
          )
  @tables ~w(users families family_memberships point_sources points)

  setup do
    previous = Application.get_env(:dawarich, :rails_secret)

    Application.put_env(
      :dawarich,
      :rails_secret,
      "phoenix-a2-cookie-fixture-secret-not-for-production"
    )

    on_exit(fn -> Application.put_env(:dawarich, :rails_secret, previous) end)
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    bandit =
      start_supervised!(
        {Bandit,
         [plug: {Dawarich.ApiEndpointCase, [api_golden: true, api_now: ~U[2026-10-05 12:00:00Z]]}] ++
           Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    %{port: port, upstream: upstream}
  end

  for kase <- @golden["cases"] do
    @kase kase
    @tag golden_case: String.to_atom(kase["name"])
    test "golden #{kase["name"]}", %{port: port, upstream: upstream} do
      seed!(@kase["setup"])
      for sql <- @kase["fault"] ++ @kase["phoenix_fault"], do: Repo.query!(sql)
      client = connect(port)
      send_raw(client, raw(@kase["request"]))

      expected = difference(@kase)
      owned(expected, client)

      if @kase["name"] == "replay_coordinate_text" do
        assert Repo.query!("SELECT count(*) FROM point_sources").rows == [
                 [length(@kase["setup"]["point_sources"])]
               ]
      end

      assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)
    end
  end

  defp difference(%{"name" => "replay_coordinate_text"} = kase) do
    assert [%{"lonlat" => nil}] = kase["rows"]
    assert kase["points_count"] == 1
    failed = @captured["replay_boolean_battery"]["response"]

    kase
    |> Map.put("response", failed)
    |> Map.put("rows", [])
    |> Map.put("commands", [])
    |> Map.put("points_count", 0)
  end

  defp difference(kase), do: kase

  defp seed!(setup) do
    for table <- @tables, row <- setup[table] do
      Repo.query!(
        "INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table}, $1::text::json)",
        [Jason.encode!(row)]
      )
    end

    for table <- @tables,
        do:
          Repo.query!(
            "SELECT setval(pg_get_serial_sequence('#{table}', 'id'), GREATEST((SELECT max(id) FROM #{table}), 1))"
          )
  end

  defp raw(%{"target" => target, "headers" => headers, "body" => body}) do
    lines = Enum.map(headers, fn [name, value] -> "#{name}: #{value}\r\n" end)
    ["POST #{target} HTTP/1.1\r\n", lines, "Content-Length: #{byte_size(body)}\r\n\r\n", body]
  end

  defp owned(kase, client) do
    {status, headers, body} = read_response(client)
    headers = Dawarich.Test.GoldenCookies.headers(headers, kase, ~U[2026-10-05 12:00:00Z])
    expected = kase["response"]
    assert is_map(expected["headers"]), "Rails capture lacks terminal response headers"
    assert is_list(kase["rows"]), "Rails capture lacks database effects"
    ids = new_ids(kase)
    id_free? = normalize(body, ids) == body

    names =
      headers
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Kernel.--(["date", "content-length" | kase["ignore"]])

    assert status == expected["status"]
    assert normalize(body, ids) == expected["body"]
    assert Enum.sort(names) == Enum.sort(Map.keys(expected["headers"]) -- kase["ignore"])

    for name <- names -- ["etag", "x-request-id", "x-runtime"],
        do: assert(values(headers, name) == [expected["headers"][name]], name)

    for [etag] <- [values(headers, "etag")] do
      assert etag ==
               ~s(W/") <>
                 binary_part(Base.encode16(:crypto.hash(:sha256, body), case: :lower), 0, 32) <>
                 ~s(")

      if id_free?, do: assert(etag == expected["headers"]["etag"])
    end

    assert values(headers, "content-length") == [Integer.to_string(byte_size(body))]
    if id_free?, do: assert(byte_size(body) == expected["content_length"])
    assert [runtime] = values(headers, "x-runtime")
    assert runtime =~ ~r/\A\d+\.\d{6}\z/

    request_id = values(headers, "x-request-id")

    case for(
           [name, value] <- kase["request"]["headers"],
           String.downcase(name) == "x-request-id",
           do: value
         ) do
      [] ->
        assert [uuid] = request_id
        assert uuid =~ ~r/\A[0-9a-f-]{36}\z/

      [_sent] ->
        assert request_id == [expected["headers"]["x-request-id"]]
    end

    %{columns: columns, rows: rows} = Repo.query!(@golden["rows_sql"], [kase["user_id"]])

    rows =
      rows
      |> Enum.map(&Map.new(Enum.zip(columns, &1)))
      |> Jason.encode!()
      |> normalize(ids)
      |> Jason.decode!()

    assert rows == kase["rows"]

    assert Repo.query!("SELECT points_count FROM users WHERE id = $1", [kase["user_id"]]).rows ==
             [[kase["points_count"]]]

    assert commands(ids) == kase["commands"]

    if captured = kase["database_after"] do
      for table <- ~w(users families family_memberships) do
        expected =
          if kase["name"] == "replay_coordinate_text" and table == "users",
            do: Enum.map(captured[table], &Map.put(&1, "points_count", 0)),
            else: captured[table]

        relation =
          if table == "family_memberships" and kase["name"] == "owntracks_friends_failure",
            do: "family_memberships_a3",
            else: table

        actual =
          Repo.query!("SELECT row_to_json(t)::text FROM #{relation} t ORDER BY id").rows
          |> Enum.map(fn [row] -> Jason.decode!(row) end)

        assert actual == expected
      end

      expected_sources =
        if kase["name"] == "replay_coordinate_text",
          do: kase["setup"]["point_sources"],
          else: captured["point_sources"]

      sources =
        Repo.query!("SELECT row_to_json(t)::text FROM point_sources t ORDER BY id").rows
        |> Enum.map(fn [row] -> Jason.decode!(row) end)

      project = fn row -> Map.drop(row, ~w(id created_at updated_at)) end
      assert Enum.map(sources, project) == Enum.map(expected_sources, project)

      for source <- sources -- kase["setup"]["point_sources"],
          do: assert(source["created_at"] == source["updated_at"])

      expected_others = Enum.reject(captured["points"], &(&1["user_id"] == kase["user_id"]))

      others =
        Repo.query!("SELECT row_to_json(t)::text FROM points t WHERE user_id != $1 ORDER BY id", [
          kase["user_id"]
        ]).rows
        |> Enum.map(fn [row] -> Jason.decode!(row) end)

      assert others == expected_others
    end
  end

  defp new_ids(kase) do
    Repo.query!("SELECT id FROM points WHERE user_id = $1 ORDER BY id", [kase["user_id"]]).rows
    |> List.flatten()
    |> Kernel.--(kase["setup_point_ids"])
    |> Enum.with_index()
    |> Map.new(fn {id, i} -> {id, "new:#{i}"} end)
  end

  defp normalize(text, ids) do
    Regex.replace(~r/"id":(\d+)/, text, fn whole, id ->
      case ids[String.to_integer(id)] do
        nil -> whole
        token -> ~s("id":"#{token}")
      end
    end)
  end

  defp commands(ids) do
    for [kind, payload] <-
          Repo.query!("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id").rows do
      case kind do
        "points.tile_epoch" ->
          %{
            "kind" => kind,
            "years" => payload["timestamps"] |> Enum.map(&year/1) |> Enum.uniq() |> Enum.sort()
          }

        "points.live_broadcast" ->
          assert payload["broadcast_id"] =~ ~r/\A[0-9a-f-]{36}\z/

          payload =
            payload
            |> Map.delete("broadcast_id")
            |> Map.update!("payloads", fn list ->
              Enum.map(list, &Map.reject(&1, fn {_k, v} -> is_nil(v) end))
            end)

          %{
            "kind" => kind,
            "payload" => payload |> Jason.encode!() |> normalize(ids) |> Jason.decode!()
          }

        _ ->
          payload =
            Map.update(payload, "payloads", nil, fn list ->
              Enum.map(list, &Map.reject(&1, fn {_k, v} -> is_nil(v) end))
            end)

          %{
            "kind" => kind,
            "payload" =>
              payload
              |> Map.reject(fn {k, v} -> k == "payloads" and is_nil(v) end)
              |> Jason.encode!()
              |> normalize(ids)
              |> Jason.decode!()
          }
      end
    end
  end

  defp year(ts), do: ts |> DateTime.from_unix!() |> Map.fetch!(:year) |> max(1970) |> min(2100)
end
