defmodule DawarichWeb.AchievementUnlocksTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Repo
  alias Dawarich.Test.{ParityHTML, RailsUser, RawHTTP}
  alias DawarichWeb.RailsCsrf
  alias DawarichWeb.AchievementActions.Unlocks

  @now ~U[2026-10-04 22:30:00.000000Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    for id <- [44001, 44002],
        do:
          RailsUser.insert!(%{
            id: id,
            email: "unlocks-#{id}@example.invalid",
            settings: %{"locale" => "en", "timezone" => "Europe/Berlin"}
          })

    Dawarich.Test.AchievementSilhouettes.clear()
    on_exit(&Dawarich.Test.AchievementSilhouettes.clear/0)
    :ok
  end

  for locale <- ~w(en de es fr pl ca zh) do
    @locale locale
    test "answers next busy empty seen and dismiss as the Rails JSON client expects in #{locale}" do
      rows("UPDATE users SET settings=settings||$1 WHERE id=44001", [%{"locale" => @locale}])
      assert run("/achievements/unlocks/next").status == 204
      state = %{"earned" => %{"FR" => "2026-10-04T22:30:00Z", "DE" => "2026-10-04T22:30:00Z"}}

      rows(
        "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES(44001,'exploration',$1,now(),now())",
        [state]
      )

      square = "MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))"

      rows(
        "INSERT INTO countries(iso_a2,iso_a3,name,geom,created_at,updated_at) VALUES('FR','FRA','France',ST_GeomFromText($1,4326),now(),now())",
        [square]
      )

      event(42301, "FR")
      event(42302, "DE")
      event(42303, "ES", 44002)
      next = run("/achievements/unlocks/next")
      assert next.status == 200
      data = Jason.decode!(next.resp_body)
      assert data["id"] == 42301 and data["batch_end_id"] == 42302 and data["remaining"] == 2
      assert data["token"] =~ ~r/\A[0-9a-f]{32}\z/
      expected = File.read!("test/fixtures/achievement_unlocks/#{@locale}_next.html")
      assert ParityHTML.normalize(data["html"]) == ParityHTML.normalize(expected)
      assert get_resp_header(next, "content-type") == ["application/json; charset=utf-8"]
      assert get_resp_header(next, "cache-control") == ["max-age=0, private, must-revalidate"]
      busy = run("/achievements/unlocks/next")
      assert busy.status == 409 and Jason.decode!(busy.resp_body) == %{"retry_after" => 2}
      assert get_resp_header(busy, "cache-control") == ["no-cache"]

      resumed =
        run(
          "/achievements/unlocks/next",
          %{"claim_token" => data["token"], "batch_end_id" => "42302"},
          form: true
        )

      assert Jason.decode!(resumed.resp_body) == data
      event(42304, "PL")

      for value <- ["0", "-1", "+1", "01", "abc", "9223372036854775808", "10000000000000000000"] do
        assert run("/achievements/unlocks/#{value}/seen", %{"claim_token" => data["token"]}).status ==
                 400
      end

      for value <- [
            nil,
            0,
            -1,
            "0",
            "-1",
            "01",
            "1.0",
            " 1",
            "abc",
            42302.0,
            "9223372036854775808"
          ] do
        result = run("/achievements/unlocks/dismiss", %{"batch_end_id" => value})
        assert result.status == 400 and result.resp_body == ""
      end

      for token <- [nil, "", " \n\t"] do
        assert run("/achievements/unlocks/42301/seen", %{"claim_token" => token}).status == 400
      end

      for {id, token} <- [
            {42301, "wrong"},
            {42303, "wrong"},
            {9_223_372_036_854_775_807, "wrong"}
          ] do
        assert run("/achievements/unlocks/#{id}/seen", %{"claim_token" => token}).status == 409
      end

      for form <- [false, true] do
        token = if form, do: "different-nonblank", else: data["token"]
        result = run("/achievements/unlocks/42301/seen", %{"claim_token" => token}, form: form)
        assert result.status == 204 and result.resp_body == ""
        assert get_resp_header(result, "content-type") == []
      end

      result = run("/achievements/unlocks/dismiss", %{"batch_end_id" => 42302})
      assert result.status == 204 and get_resp_header(result, "cache-control") == ["no-cache"]

      assert [[42303], [42304]] ==
               rows("SELECT id FROM achievement_unlock_events WHERE seen_at IS NULL ORDER BY id")

      assert run("/achievements/unlocks/next", %{"batch_end_id" => 42302}).status == 204
      assert rows("SELECT state FROM achievement_progresses WHERE user_id=44001") == [[state]]
      assert rows("SELECT count(*) FROM flipper_gates WHERE feature_key='achievements'") == [[0]]
    end
  end

  test "skips invisible cards at most ten times without postclaim fallback" do
    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES(44001,'exploration','{}',now(),now())"
    )

    for id <- 42501..42511, do: event(id, "missing_#{id}", 44001, "set")
    pid = self()
    handler = "unlock-state-reads"

    :telemetry.attach(
      handler,
      [:dawarich, :repo, :query],
      fn _, _, metadata, _ ->
        if metadata.query =~ "SELECT state FROM achievement_progresses",
          do: send(pid, :state_read)
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    result = run("/achievements/unlocks/next")
    assert result.status == 204 and result.resp_body == ""

    assert [[42511, nil, nil, nil]] ==
             rows(
               "SELECT id,seen_at,claimed_at,claim_token FROM achievement_unlock_events WHERE seen_at IS NULL ORDER BY id"
             )

    assert state_reads() == 1
    assert rows("SELECT state FROM achievement_progresses WHERE user_id=44001") == [[%{}]]
    state_reads()
    rows("DELETE FROM achievement_unlock_events")
    event(42521, "FR")
    event(42522, "PL")
    server = RawHTTP.listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    context = Map.put(context(), :render, fn _, _, _ -> raise "synthetic render failure" end)

    result =
      run("/achievements/unlocks/next", %{},
        context: context,
        upstream: {{127, 0, 0, 1}, server.port}
      )

    assert result.status == 500 and result.halted

    assert [[42521]] ==
             rows("SELECT id FROM achievement_unlock_events WHERE claim_token IS NOT NULL")

    assert [[2]] == rows("SELECT count(*) FROM achievement_unlock_events WHERE seen_at IS NULL")
    assert {:error, :timeout} == :gen_tcp.accept(server.listen, 0)
    assert state_reads() == 1
  end

  defp context, do: %{clock: fn -> @now end}

  defp state_reads do
    receive do
      :state_read -> 1 + state_reads()
    after
      0 -> 0
    end
  end

  defp event(id, key, user \\ 44001, kind \\ "geography"),
    do:
      rows(
        "INSERT INTO achievement_unlock_events(id,user_id,kind,key,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$5)",
        [id, user, kind, key, DateTime.to_naive(@now)]
      )

  defp run(path, params \\ %{}, opts \\ []) do
    session = RailsUser.session(44001)
    token = RailsCsrf.masked_form_token(session, path, "POST")
    form = Keyword.get(opts, :form, false)

    raw =
      if form,
        do: URI.encode_query(Map.put(params, "authenticity_token", token)),
        else: Jason.encode!(params)

    conn =
      build_conn("POST", path, raw)
      |> put_req_header("accept", "application/json")
      |> put_req_header(
        "content-type",
        if(form, do: "application/x-www-form-urlencoded", else: "application/json")
      )
      |> put_req_header("content-length", to_string(byte_size(raw)))
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))

    conn = if form, do: conn, else: put_req_header(conn, "x-csrf-token", token)
    Unlocks.call(conn, Keyword.put_new(opts, :context, context()))
  end

  defp rows(sql, args \\ []), do: Repo.query!(sql, args, log: false).rows
end
