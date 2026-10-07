defmodule DawarichWeb.A12f3aTClosureTest do
  use Dawarich.IngestCase, async: false

  import Phoenix.ConnTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  alias Dawarich.Jobs.Ownership
  @endpoint DawarichWeb.Endpoint
  @now ~U[2026-10-03 10:00:00.000000Z]

  defmodule ExportQueryFailure do
    def query!(_sql, _params, _opts), do: raise("synthetic trip export query failure")
  end

  setup do
    previous = Application.get_env(:dawarich, :jobs_repo)
    hosted = System.get_env("SELF_HOSTED")
    jwt = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "synthetic-trip-closure")
    Application.put_env(:dawarich, :jobs_repo, Repo)

    on_exit(fn ->
      if jwt, do: System.put_env("JWT_SECRET_KEY", jwt), else: System.delete_env("JWT_SECRET_KEY")
      Application.put_env(:dawarich, :jobs_repo, previous)
      if hosted, do: System.put_env("SELF_HOSTED", hosted), else: System.delete_env("SELF_HOSTED")
    end)

    user =
      RailsUser.insert!(%{
        id: 9801,
        email: "trip-closure@example.test",
        settings: %{"timezone" => "Europe/Berlin"},
        active_until: ~N[3026-10-03 12:00:00]
      })

    Ownership.put!(Repo, "command:trips.calculate", :oban)
    %{user: Dawarich.Accounts.get(user.id)}
  end

  @tag a12f3a_t01: true
  test "T01: trip index and form navigation tails matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    TripsSeeds.trip!(%{id: 980_101, user_id: user.id, path: [[12.37, 51.33], [12.38, 51.34]]})

    for mode <- ["true", "false", nil] do
      if mode, do: System.put_env("SELF_HOSTED", mode), else: System.delete_env("SELF_HOSTED")

      for path <- ["/trips", "/trips/new", "/trips/980101/edit"] do
        conn = get(RailsUser.signed_in(user.id), path)
        assert conn.status == 200, "#{mode} #{path}"
        assert conn.resp_body =~ "trip"
        assert get(build_conn(), path).status == 302
      end
    end

    foreign = TripsSeeds.user!(9802)
    TripsSeeds.trip_source!(980_102, foreign.id)
    Repo.query!("UPDATE trips SET trip_source_id=$2 WHERE id=$1", [980_101, 980_102])
    assert Dawarich.TripList.gate(user, 1) == :rails
    assert commands() == []
  end

  @tag a12f3a_t06: true
  test "T06: trip calculation producers and show callback matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    System.put_env("SELF_HOSTED", "false")
    TripsSeeds.trip!(%{id: 980_601, user_id: user.id, path: nil})
    assert Dawarich.Trips.ShowCalculation.admitted?(Repo, user, 980_601, @now)
    assert {:ok, :queued} = Dawarich.Trips.ShowCalculation.run(Repo, user, 980_601, %{now: @now})

    assert Repo.query!("SELECT payload FROM job_outbox WHERE command_type='trips.calculate'").rows ==
             [[%{"trip_id" => 980_601, "distance_unit" => "km"}]]

    TripsSeeds.trip!(%{
      id: 980_602,
      user_id: user.id,
      path: nil,
      source_identifier: "synthetic",
      started_at: ~N[2026-11-01 10:00:00],
      ended_at: ~N[2026-11-02 10:00:00]
    })

    assert {:ok, :ready} = Dawarich.Trips.ShowCalculation.run(Repo, user, 980_602, %{now: @now})
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[1]]
    assert get(RailsUser.signed_in(user.id), "/trips/980601").status == 200
    assert commands() == []
  end

  @tag a12f3a_t03: true
  test "T03: trip photos provider handoff matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    oracle = File.read!("test/fixtures/trips/a12f3a-t03.json") |> Jason.decode!()

    settings =
      Map.merge(user.settings, %{
        "immich_url" => "https://photos.example.test",
        "immich_api_key" => "synthetic",
        "photoprism_url" => "https://photos.example.test",
        "photoprism_api_key" => "synthetic"
      })

    Repo.query!("UPDATE users SET settings=$2, api_key=$3 WHERE id=$1", [
      user.id,
      settings,
      "a8r-k-98980"
    ])

    user = Dawarich.Accounts.get(user.id)
    first = ~N[2026-10-02 22:30:00]
    last = ~N[2026-10-04 01:00:00]

    TripsSeeds.trip!(%{
      id: 980_301,
      user_id: user.id,
      started_at: first,
      ended_at: last,
      path: [[12.37, 51.33], [12.38, 51.34]]
    })

    keys =
      ~w(id latitude longitude localDateTime capturedAt originalFileName city state country type orientation source)

    assets =
      Enum.map(oracle["assets"], fn asset -> Map.merge(Map.new(keys, &{&1, nil}), asset) end)

    key =
      Dawarich.Photos.ProviderCache.key(user.id, "2026-10-02T22:30:00Z", "2026-10-04T01:00:00Z")

    assert {:ok, _} = Dawarich.Photos.ProviderCache.put(key, assets)
    assert {:ok, ^assets} = Dawarich.Photos.ProviderCache.get(key)
    on_exit(fn -> Dawarich.Photos.ProviderCache.invalidate(user.id) end)
    result = Dawarich.Trips.Photos.load(user, first, last, "Europe/Berlin")

    assert Enum.map(
             result.photos,
             &Map.new(&1, fn {key, value} -> {Atom.to_string(key), value} end)
           ) == oracle["photos"]

    assert Map.new(result.days, fn {day, photos} ->
             {Date.to_iso8601(day), Enum.map(photos, & &1.id)}
           end) ==
             Map.new(oracle["days"], fn {day, photos} -> {day, Enum.map(photos, & &1["id"])} end)

    assert Enum.sort(Enum.map(result.previews, & &1.id)) ==
             Enum.sort(Enum.map(oracle["previews"], & &1["id"]))

    assert result.sources == oracle["sources"]
    assert {:ok, page} = Dawarich.TripPage.load(user, 980_301, @now)
    assert Enum.find(page.days, &(&1.date == ~D[2026-10-03])).photos != []
    conn = get(RailsUser.signed_in(user.id), "/trips/980301")
    assert conn.status == 200
    assert conn.resp_body =~ "/api/v1/photos/late/thumbnail.jpg"
    assert commands() == []
  end

  @tag a12f3a_t05: true
  test "T05: trip create and update coercions matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    System.put_env("SELF_HOSTED", "false")

    attrs = %{
      "name" => "Auwald",
      "started_at" => "2026-10-03T09:00",
      "ended_at" => "2026-10-04T19:00"
    }

    conn = submit(user, "/trips", %{"trip" => attrs})
    assert conn.status == 302
    [[id]] = Repo.query!("SELECT id FROM trips WHERE user_id=$1", [user.id]).rows
    Repo.query!("DELETE FROM job_outbox")

    assert submit(user, "/trips/#{id}", %{"_method" => "patch", "trip" => %{"name" => "Renamed"}}).status ==
             303

    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]

    assert submit(user, "/trips", %{"trip" => %{"name" => ""}}, "text/vnd.turbo-stream.html").status ==
             500

    assert Repo.query!("SELECT count(*) FROM trips").rows == [[1]]
    assert commands() == []
  end

  @tag a12f3a_t04: true
  test "T04: trip rich description and dependent deletion matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    oracle = File.read!("test/fixtures/trips/a12f3a-t04.json") |> Jason.decode!()

    for item <- oracle["cases"], not is_nil(item["rendered"]) do
      name = item["name"]
      assert {:ok, description} = Dawarich.Trips.RichContent.read(item["body"])

      assert {name, IO.iodata_to_binary(Dawarich.TripDescription.html(description))} ==
               {name, item["rendered"]}
    end

    TripsSeeds.trip!(%{id: 980_401, user_id: user.id})
    TripsSeeds.rich_text!(980_401, "<p>Rich notes</p><script>alert(1)</script>")
    assert {:ok, form} = Dawarich.Trips.WebForm.load(Repo, user, 980_401, %{})
    assert form.description =~ "<script>"
    assert {:ok, displayed} = Dawarich.Trips.RichContent.read(form.description)
    refute displayed =~ "<script>"
    assert {:ok, :deleted} = Dawarich.Trips.WebDelete.run(Repo, user, 980_401, %{})

    assert Repo.query!("SELECT count(*) FROM action_text_rich_texts WHERE record_id=$1", [980_401]).rows ==
             [[0]]

    assert commands() == []
  end

  @tag a12f3a_t10: true
  test "T10: trip export http and producer matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    oracle = File.read!("test/fixtures/trips/a12f3a-t10.json") |> Jason.decode!()
    entry = Enum.find(oracle["effects"], &(&1["name"] == "export_gpx_1_oban"))
    [trip] = entry["before"]["trips"]

    TripsSeeds.trip!(%{
      id: 980_1001,
      user_id: user.id,
      name: trip["name"],
      started_at: ~N[2026-10-02 22:30:00],
      ended_at: ~N[2026-10-04 01:00:00]
    })

    assert {:ok, export} = Dawarich.Trips.WebExport.prepare(Repo, user, 980_1001, "gpx", %{})
    assert export.name == hd(entry["after"]["exports"])["name"]
    assert export.start_at == ~N[2026-10-02 22:30:00.000000]
    assert export.end_at == ~N[2026-10-04 01:00:00.000000]

    assert {:invalid, :format} =
             Dawarich.Trips.WebExport.prepare(Repo, user, 980_1001, "csv", %{})

    Ownership.put!(Repo, "command:exports.points", :oban)
    assert submit(user, "/trips/9801001/export?file_format=gpx", %{}).status == 302
    assert Repo.query!("SELECT count(*) FROM exports WHERE user_id=$1", [user.id]).rows == [[1]]
    assert Repo.query!("SELECT command_type FROM job_outbox").rows == [["exports.points"]]
    assert commands() == []
  end

  @tag a12f3a_t08: true
  test "T08: trip notes create and upsert matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    TripsSeeds.trip!(%{
      id: 980_801,
      user_id: user.id,
      started_at: ~N[2026-10-02 22:30:00],
      ended_at: ~N[2026-10-04 01:00:00]
    })

    attrs = %{"date" => "Oct 3 2026", "body" => "\nAuwald"}

    assert {:ok, %{note: note}} =
             Dawarich.Trips.WebNotes.run(Repo, :create, user, 980_801, nil, attrs, %{now: @now})

    assert note.body == "\nAuwald"
    assert note.noted_at == ~N[2026-10-03 12:00:00.000000]

    assert submit(user, "/trips/980801/notes", %{"note" => attrs}, "text/vnd.turbo-stream.html").status ==
             200

    assert Repo.query!("SELECT body FROM notes WHERE attachable_id=$1", [980_801]).rows == [
             ["\nAuwald"]
           ]

    assert {:invalid_date} =
             Dawarich.Trips.WebNotes.run(
               Repo,
               :create,
               user,
               980_801,
               nil,
               %{attrs | "date" => "2026-02-31"},
               %{now: @now}
             )

    assert commands() == []
  end

  @tag a12f3a_t02: true
  test "T02: trip show itinerary and future plans matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    TripsSeeds.trip!(%{
      id: 980_201,
      user_id: user.id,
      path: nil,
      source_identifier: "synthetic",
      started_at: ~N[2026-11-01 10:00:00],
      ended_at: ~N[2026-11-02 10:00:00]
    })

    assert {:ok, page} = Dawarich.TripPage.load(user, 980_201, @now)
    assert page.map_state == :future
    assert get(RailsUser.signed_in(user.id), "/trips/980299").status == 404
    assert get(RailsUser.signed_in(user.id), "/trips/980299/edit").status == 404

    TripsSeeds.rich_text!(
      980_201,
      "<action-text-attachment sgid=\"invalid\"></action-text-attachment>"
    )

    assert get(RailsUser.signed_in(user.id), "/trips/980201").status == 200
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
    assert commands() == []
  end

  @tag a12f3a_t_edges_inactive: true
  test "T01 T05 T07: inactive accounts receive the source redirect before trip effects", %{
    user: user
  } do
    TripsSeeds.trip!(%{id: 980_701, user_id: user.id})
    Repo.query!("UPDATE users SET active_until=NULL WHERE id=$1", [user.id])
    user = Dawarich.Accounts.get(user.id)

    for mode <- ["true", "false", nil] do
      if mode, do: System.put_env("SELF_HOSTED", mode), else: System.delete_env("SELF_HOSTED")

      requests = [
        fn -> get(RailsUser.signed_in(user.id), "/trips/new") end,
        fn -> submit(user, "/trips", %{"trip" => %{"name" => "Inactive"}}) end,
        fn -> submit(user, "/trips/980701/recalculate", %{}) end,
        fn -> submit(user, "/trips/980799/recalculate", %{}) end
      ]

      for request <- requests do
        conn = request.()
        assert conn.status == 303
        assert Plug.Conn.get_resp_header(conn, "location") == ["http://www.example.com/"]

        assert Dawarich.Test.RailsFormRequests.rails_session(conn)["flash"]["flashes"]["notice"] ==
                 "Your account is not active."
      end
    end

    assert Repo.query!("SELECT count(*) FROM trips WHERE user_id=$1", [user.id]).rows == [[1]]
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
    assert commands() == []
  end

  @tag a12f3a_t_edges_export: true
  test "T10: export body format overrides query and prepare failures remain terminal", %{
    user: user
  } do
    Ownership.put!(Repo, "command:exports.points", :oban)
    TripsSeeds.trip!(%{id: 980_1002, user_id: user.id})
    conn = submit(user, "/trips/9801002/export?file_format=gpx", %{"file_format" => "json"})
    assert conn.status == 302

    assert Repo.query!("SELECT file_format FROM exports WHERE user_id=$1", [user.id]).rows == [
             [0]
           ]

    assert Repo.query!("SELECT command_type FROM job_outbox").rows == [["exports.points"]]

    Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [
      user.id,
      %{"timezone" => "Unknown/Zone"}
    ])

    conn = submit(user, "/trips/9801002/export", %{"file_format" => "gpx"})
    assert conn.status == 422
    assert Plug.Conn.get_resp_header(conn, "location") == ["http://www.example.com/trips/9801002"]

    assert Dawarich.Test.RailsFormRequests.rails_session(conn)["flash"]["flashes"]["alert"] ==
             "Export failed to initiate. Please try again."

    assert Repo.query!("SELECT count(*) FROM exports WHERE user_id=$1", [user.id]).rows == [[1]]
    Application.put_env(:dawarich, :jobs_repo, ExportQueryFailure)
    exception = submit(user, "/trips/9801002/export", %{"file_format" => "gpx"})
    assert exception.status == 422

    assert Plug.Conn.get_resp_header(exception, "location") == [
             "http://www.example.com/trips/9801002"
           ]

    assert Repo.query!("SELECT count(*) FROM exports WHERE user_id=$1", [user.id]).rows == [[1]]
    assert commands() == []
  end

  @tag a12f3a_t05_edges: true
  test "T05: legacy date strings and ignored scalar attributes retain source casting", %{
    user: user
  } do
    expected = [
      {"2026-10-03", ~N[2026-10-02 22:00:00.000000]},
      {"October 3 2026", ~N[2026-10-02 22:00:00.000000]},
      {"2026-10-03T09:00CET", ~N[2026-10-03 08:00:00.000000]},
      {"2026-02-31T09:00", ~N[2026-03-03 08:00:00.000000]},
      {"2026-10-03 09:00", ~N[2026-10-03 07:00:00.000000]},
      {"2026-10-03 09:00:00.987654", ~N[2026-10-03 07:00:00.987654]},
      {"03/10/2026 09:00", ~N[2026-10-03 07:00:00.000000]}
    ]

    for {raw, stamp} <- expected do
      attrs = %{
        "name" => "Auwald",
        "started_at" => raw,
        "ended_at" => "2026-10-04T19:00",
        "ignored" => "source strong params"
      }

      assert {:ok, changes} =
               Dawarich.Trips.WebParams.parse(user, attrs, %{}, %{repo: Repo, now: @now})

      assert NaiveDateTime.compare(changes.started_at, stamp) == :eq
    end

    conn =
      submit(user, "/trips", %{
        "trip" => %{
          "name" => "Date",
          "started_at" => "October 3 2026",
          "ended_at" => "2026-10-04T19:00",
          "ignored" => "source strong params"
        }
      })

    assert conn.status == 302

    invalid =
      submit(user, "/trips", %{
        "trip" => %{"name" => "Date", "started_at" => "invalid", "ended_at" => "2026-10-04T19:00"}
      })

    assert invalid.status == 422
    assert Repo.query!("SELECT count(*) FROM trips WHERE user_id=$1", [user.id]).rows == [[1]]
    assert commands() == []
  end

  defp submit(user, path, params, accept \\ "text/html") do
    session = RailsUser.session(user.id)
    params = Map.put(params, "authenticity_token", DawarichWeb.RailsCsrf.masked_token(session))

    Dawarich.Test.RailsFormRequests.post_form(
      session,
      Plug.Conn.Query.encode(params),
      [{"accept", accept}],
      path
    )
  end
end
