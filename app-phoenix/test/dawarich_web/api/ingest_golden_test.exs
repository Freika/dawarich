defmodule DawarichWeb.Api.IngestGoldenTest do
  use Dawarich.IngestCase, async: false
  import Dawarich.Test.RawHTTP

  @golden "test/fixtures/ingest/golden.json" |> File.read!() |> Jason.decode!()
  @tables ~w(users families family_memberships point_sources points)

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    %{port: port, upstream: upstream}
  end

  for kase <- @golden["cases"] do
    @kase kase
    test "golden #{kase["name"]}", %{port: port, upstream: upstream} do
      seed!(@kase["setup"])
      for sql <- @kase["fault"] ++ @kase["phoenix_fault"], do: Repo.query!(sql)
      client = connect(port)
      send_raw(client, raw(@kase["request"]))

      if @kase["expect"] == "replay",
        do: replayed(@kase, upstream, client),
        else: owned(@kase, client)
    end
  end

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
    expected = kase["response"]
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
  end

  defp replayed(kase, upstream, client) do
    request = kase["request"]
    puma = accept(upstream)
    {head, rest} = read_head(puma)

    assert request_line(head) == "POST #{request["target"]} HTTP/1.1"

    assert read_at_least(puma, rest, byte_size(request["body"]))
           |> binary_part(0, byte_size(request["body"])) == request["body"]

    for [name, value] <- request["headers"],
        do: assert(header(head, String.downcase(name)) == [value], name)

    %{"status" => status, "body" => body} = kase["response"]
    reply(puma, "HTTP/1.1 #{status} Rails\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}")
    assert {^status, _, ^body} = read_response(client)

    assert Repo.query!("SELECT count(*) FROM points WHERE user_id = $1", [kase["user_id"]]).rows ==
             [[length(kase["setup_point_ids"])]]

    assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands").rows == [[0]]
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
