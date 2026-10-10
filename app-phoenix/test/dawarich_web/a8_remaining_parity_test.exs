defmodule DawarichWeb.A8RemainingParityTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.Test.{FrameSeeds, TripsSeeds, RailsUser}
  alias Dawarich.Jobs.Ownership
  @endpoint DawarichWeb.Endpoint
  @places File.read!("test/fixtures/places/remaining/effects.json")
          |> Jason.decode!()
          |> Map.fetch!("effects")
  @trips File.read!("test/fixtures/trips/remaining/effects.json")
         |> Jason.decode!()
         |> Map.fetch!("effects")
  @trip_responses File.read!("test/fixtures/trips/remaining/responses.json")
                  |> Jason.decode!()
                  |> Map.fetch!("responses")
  @tables ~w(trips places notes taggings action_text_rich_texts exports job_outbox)
  @now ~U[2026-10-03 10:00:00.000000Z]

  defp snapshot do
    Map.new(@tables, fn table ->
      key = if table == "job_outbox", do: "event_id", else: "id"
      {table, Repo.query!("SELECT to_jsonb(t) FROM #{table} t ORDER BY #{key}").rows}
    end)
    |> Map.put("commands", commands())
  end

  defp seed_trip(name) do
    entry = Enum.find(@trips, &(&1["name"] == name))
    actor = entry["before"]["actor"]

    RailsUser.insert!(%{
      id: actor["id"],
      email: "a8-boundary-#{actor["id"]}@example.invalid",
      api_key: "a8r-k-#{actor["id"]}",
      settings: actor["settings"],
      active_until: ~N[3026-10-03 10:00:00]
    })

    for row <- entry["before"]["trips"] do
      TripsSeeds.trip!(%{
        id: row["id"],
        user_id: row["user_id"],
        name: row["name"],
        demo: row["demo"],
        distance: row["distance"],
        visited_countries: row["visited_countries"],
        path: row["path"],
        started_at: naive(row["started_at"]),
        ended_at: naive(row["ended_at"]),
        created_at: naive(row["created_at"]),
        updated_at: naive(row["updated_at"]),
        source_identifier: row["source_identifier"]
      })
    end

    for row <- entry["before"]["action_text_rich_texts"],
        do: TripsSeeds.rich_text!(row["record_id"], row["body"])

    Ownership.put!(
      Repo,
      "command:trips.calculate",
      String.to_existing_atom(entry["request"]["owner"])
    )

    {entry, Dawarich.Accounts.get(actor["id"])}
  end

  defp naive(text), do: text |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

  defp submit(entry, user) do
    req = entry["request"]
    session = RailsUser.session(user.id)

    params =
      Map.put(req["params"], "authenticity_token", DawarichWeb.RailsCsrf.masked_token(session))

    params =
      if String.upcase(req["method"]) == "POST",
        do: params,
        else: Map.put(params, "_method", String.downcase(req["method"]))

    raw = Plug.Conn.Query.encode(params)

    conn =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header("accept", req["accept"])
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(raw)))
      |> assign(:now, @now)

    {fn -> dispatch(conn, @endpoint, :post, req["path"], raw) end, raw}
  end

  defp replay(upstream, run, raw) do
    before = snapshot()

    {{_line, received}, conn} =
      forwarded(upstream, fn ->
        conn = run.()
        assert conn.status == 204
        conn
      end)

    assert conn.status == 204
    assert received == raw
    assert snapshot() == before
  end

  test "out of range place tag IDs replay before create or demo adoption" do
    upstream = upstream!()

    for name <- ~w(create_ordinary_turbo_false update_demo_html_false) do
      entry = Enum.find(@places, &(&1["name"] == name))
      user = FrameSeeds.seed_place_remainder!(entry)

      for value <- ["9223372036854775808", String.duplicate("9", 100), "00009223372036854775808"] do
        request = entry["request"]

        attrs =
          request["params"]["place"]
          |> Map.put("tag_ids", [value])
          |> Map.put("name", "Must stay on Rails")

        entry = put_in(entry, ["request", "params", "place"], attrs)
        {run, raw} = submit(entry, user)
        replay(upstream, run, raw)
      end
    end

    assert Dawarich.Places.WebTags.supported?(%{
             "tag_ids" => ["", nil, "0", "0000", "9223372036854775807", "0009223372036854775807"]
           })

    assert Dawarich.Places.WebTags.supported?(%{
             "tag_ids" => [-9_223_372_036_854_775_808, 9_223_372_036_854_775_807]
           })

    refute Dawarich.Places.WebTags.supported?(%{"tag_ids" => [-9_223_372_036_854_775_809]})
  end

  test "remaining corpus matches responses effects markup and rollback" do
    upstream = upstream!()
    previous_jobs = Application.get_env(:dawarich, :jobs_repo)
    previous_routes = Application.get_env(:dawarich, :rails_routes)
    previous_hosted = System.get_env("SELF_HOSTED")
    Application.put_env(:dawarich, :jobs_repo, Repo)

    on_exit(fn ->
      Application.put_env(:dawarich, :jobs_repo, previous_jobs)
      Application.put_env(:dawarich, :rails_routes, previous_routes)

      if previous_hosted,
        do: System.put_env("SELF_HOSTED", previous_hosted),
        else: System.delete_env("SELF_HOSTED")
    end)

    place_entry = Enum.find(@places, &(&1["name"] == "create_ordinary_turbo_false"))
    place_user = FrameSeeds.seed_place_remainder!(place_entry)
    entry = place_entry
    user = place_user

    Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [
      user.id,
      %{"timezone" => "Mars/Phobos"}
    ])

    {run, raw} = submit(entry, user)
    replay(upstream, run, raw)
    Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [user.id, user.settings])

    for name <-
          ~w(create_oban update_name_ordinary_oban update_name_demo_sidekiq update_date_ordinary_oban update_embedded_ordinary_oban) do
      {entry, user} = seed_trip(name)
      {run, _raw} = submit(entry, user)
      conn = run.()
      expected = Enum.find(@trip_responses, &(&1["name"] == name))
      assert conn.status == expected["status"], name
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
      assert rails_session(conn)["flash"]["flashes"] == expected["flash"]
      [row] = entry["after"]["trips"]

      id =
        if name == "create_oban",
          do:
            Repo.query!("SELECT id FROM trips WHERE user_id=$1", [user.id]).rows |> hd() |> hd(),
          else: row["id"]

      assert get_resp_header(conn, "location") == ["http://www.example.com/trips/#{id}"]

      assert Repo.query!(
               "SELECT name,demo,started_at,ended_at,updated_at FROM trips WHERE id=$1",
               [id]
             ).rows ==
               [
                 [
                   row["name"],
                   row["demo"],
                   naive(row["started_at"]),
                   naive(row["ended_at"]),
                   naive(row["updated_at"])
                 ]
               ]

      for rich <- entry["after"]["action_text_rich_texts"] do
        assert Repo.query!(
                 "SELECT body FROM action_text_rich_texts WHERE record_type='Trip' AND record_id=$1",
                 [id]
               ).rows == [[rich["body"]]]
      end

      expected_outbox =
        Enum.map(entry["queue"]["outbox"], fn envelope ->
          [
            envelope["command_type"],
            envelope["command_version"],
            Map.put(envelope["payload"], "trip_id", id),
            envelope["metadata"],
            id,
            to_string(id),
            envelope["state"],
            DateTime.from_iso8601(envelope["scheduled_at"]) |> elem(1)
          ]
        end)

      assert Repo.query!(
               "SELECT command_type,command_version,payload,metadata,aggregate_id,dedupe_key,state,scheduled_at FROM job_outbox WHERE aggregate_id=$1 ORDER BY event_id",
               [id]
             ).rows == expected_outbox
    end

    for name <- ~w(create_sidekiq update_date_ordinary_sidekiq) do
      {entry, user} = seed_trip(name)
      {run, raw} = submit(entry, user)
      replay(upstream, run, raw)
    end

    {entry, user} = seed_trip("show_nil_path_sidekiq")
    path = entry["request"]["path"]
    before = snapshot()
    {{line, _}, conn} = forwarded(upstream, fn -> RailsUser.signed_in(user.id) |> get(path) end)
    assert conn.status == 204
    assert line == "GET #{path} HTTP/1.1"
    assert snapshot() == before
    Ownership.put!(Repo, "command:trips.calculate", :oban)

    Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [
      user.id,
      Map.merge(user.settings, %{
        "immich_url" => "https://photos.example.invalid",
        "immich_api_key" => "synthetic"
      })
    ])

    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    [trip] = entry["before"]["trips"]

    iso = fn raw ->
      raw
      |> naive()
      |> NaiveDateTime.truncate(:second)
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.to_iso8601()
    end

    key =
      Dawarich.Photos.ProviderCache.key(user.id, iso.(trip["started_at"]), iso.(trip["ended_at"]))

    assert {:ok, _} = Dawarich.Photos.ProviderCache.put(key, [])
    on_exit(fn -> Dawarich.Photos.ProviderCache.invalidate(user.id) end)
    conn = RailsUser.signed_in(user.id) |> get(path)
    assert conn.status == 200

    assert Repo.query!("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [trip["id"]]).rows ==
             [[1]]

    assert commands() == []

    for key <- ~w(trips places) do
      Application.put_env(:dawarich, :rails_routes, [key])

      if key == "trips" do
        {entry, user} = seed_trip("update_noop_ordinary_oban")
        {run, raw} = submit(entry, user)
        replay(upstream, run, raw)
      else
        {run, raw} = submit(place_entry, place_user)
        replay(upstream, run, raw)
      end
    end

    Application.put_env(:dawarich, :rails_routes, [])
    {run, raw} = submit(place_entry, place_user)
    System.put_env("SELF_HOSTED", "false")
    replay(upstream, run, raw)
    System.put_env("SELF_HOSTED", "true")
    session = RailsUser.session(place_user.id)

    raw =
      Plug.Conn.Query.encode(%{
        "authenticity_token" => DawarichWeb.RailsCsrf.masked_token(session),
        "place" => %{"name" => "Retained"},
        "client" => "legacy"
      })

    replay(
      upstream,
      fn -> post_form(session, raw, [{"accept", "text/vnd.turbo-stream.html"}], "/places") end,
      raw
    )

    assert commands() == []
  end
end
