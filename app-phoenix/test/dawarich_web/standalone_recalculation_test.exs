defmodule DawarichWeb.StandaloneRecalculationTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.Jobs.{Ownership, Registry}
  alias Dawarich.Test.RailsUser

  setup do
    env = Map.take(System.get_env(), ~w(DAWARICH_RAILS SELF_HOSTED JWT_SECRET_KEY MANAGER_URL))

    System.put_env(%{
      "DAWARICH_RAILS" => "off",
      "SELF_HOSTED" => "true",
      "JWT_SECRET_KEY" => Enum.join(~w(sweep6 synthetic jwt), "-"),
      "MANAGER_URL" => "https://manager.example.invalid"
    })

    for spec <- Dawarich.Redis.child_specs() ++ Dawarich.Redis.cache_child_specs(),
        do: start_supervised!(spec)

    previous_cable = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, repo: Repo)
    on_exit(fn -> Application.put_env(:dawarich, :cable, previous_cable) end)
    Dawarich.TtlCache.delete({DawarichWeb.RateLimit, "sweep6-synthetic"})

    Repo.query!("DELETE FROM phoenix.counters WHERE key LIKE '%:sweep6-synthetic'", [],
      log: false
    )

    id = user!(%{api_key: "sweep6-synthetic", plan: 1, settings: %{}})

    on_exit(fn ->
      for name <- ~w(DAWARICH_RAILS SELF_HOSTED JWT_SECRET_KEY MANAGER_URL) do
        if env[name], do: System.put_env(name, env[name]), else: System.delete_env(name)
      end

      Dawarich.Redis.cache_command([
        "DEL",
        "recalculation_pending:#{id}",
        Dawarich.Transportation.RecalculationStatus.key(id)
      ])
    end)

    Dawarich.State.put_registration_enabled(Repo, true)
    %{id: id}
  end

  @tag :sweep6_api
  test "standalone rebuild API authenticates validates queues once and preserves coexistence", %{
    id: id
  } do
    Ownership.put!(Repo, "command:users.recalculate_data", :oban)
    assert api(%{}, "absent").status == 401
    invalid = api(%{"year" => "1999"})
    assert invalid.status == oracle("invalid")["status"]
    assert Jason.decode!(invalid.resp_body) == oracle("invalid")["body"]
    response = api(%{"year" => "2024tail", "user_id" => id + 1})
    assert response.status == 202

    assert Jason.decode!(response.resp_body) == oracle("accepted")["body"]
    pending = api(%{})
    assert pending.status == oracle("pending")["status"]
    assert Jason.decode!(pending.resp_body) == oracle("pending")["body"]

    assert [["users.recalculate_data", payload]] =
             rows("SELECT command_type,payload FROM job_outbox WHERE aggregate_id=$1", [id])

    assert payload["user_id"] == id
    assert payload["year"] == 2024
    assert payload["notify"] == true
    assert {:ok, _} = Dawarich.Users.RecalculateWorker.args_from_command(1, payload)
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    Repo.query!("UPDATE users SET status=0 WHERE id=$1", [id])
    assert api(%{}).status == 401
    Dawarich.Redis.cache_command(["DEL", "recalculation_pending:#{id}"])
    Repo.query!("UPDATE users SET status=1 WHERE id=$1", [id])
    assert api(%{}).status == 202

    assert [[nil]] ==
             rows(
               "SELECT payload->'year' FROM job_outbox WHERE aggregate_id=$1 AND payload->'year'='null'::jsonb",
               [id]
             )

    Repo.query!("UPDATE users SET plan=0,active_until='3026-01-01' WHERE id=$1", [id])
    System.put_env("SELF_HOSTED", "false")
    assert api(%{}).status == 403
    System.delete_env("DAWARICH_RAILS")
    conn = Plug.Test.conn(:post, "/api/v1/recalculations")
    assert DawarichWeb.ApiClosureRoutes.deferred?(conn)

    assert Phoenix.Router.route_info(DawarichWeb.Router, "POST", conn.path_info, conn.host) ==
             :error
  end

  @tag :sweep6_transport
  test "standalone rebuild preserves native API transport and Cloud pending payment reply", %{
    id: id
  } do
    Ownership.put!(Repo, "command:users.recalculate_data", :oban)

    response =
      Plug.Test.conn(:post, "/api/v1/recalculations")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer sweep6-synthetic")
      |> DawarichWeb.Endpoint.call([])

    assert response.status == 202
    assert rows("SELECT payload->'year' FROM job_outbox WHERE aggregate_id=$1", [id]) == [[nil]]
    Repo.query!("UPDATE users SET status=3 WHERE id=$1", [id])
    System.put_env("SELF_HOSTED", "false")
    response = api(%{})
    assert response.status == oracle("payment")["status"]
    body = Jason.decode!(response.resp_body)
    assert body["error"] == oracle("payment")["error"]

    assert body["message"] ==
             Dawarich.I18n.en!("controllers.api.complete_your_subscription_to_continue")

    assert is_binary(body["resume_url"])
    assert URI.parse(body["resume_url"]).host == oracle("payment")["resume_host"]
    assert URI.parse(body["resume_url"]).path == oracle("payment")["resume_path"]
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]) == [[1]]
  end

  @tag :sweep6_web
  test "standalone transportation rebuild claims its producer and resolves the existing worker",
       %{id: id} do
    entry =
      Enum.find(
        Dawarich.Standalone.job_entries(),
        &(&1.key == "command:transportation.user_reclassify")
      )

    assert entry != nil
    assert entry.worker == Dawarich.Transportation.UserReclassifyWorker
    refute entry.claimable
    Ownership.put!(Repo, entry.key, :oban)
    assert Registry.command("transportation.user_reclassify") == {:ok, entry.worker}

    Repo.query!("UPDATE users SET encrypted_password=$2 WHERE id=$1", [
      id,
      "$2a$04$" <> String.duplicate("phoenixa5fixture", 4)
    ])

    session = RailsUser.session(id)
    response = web(session, "text/html")
    assert response.status == 302
    assert get_resp_header(response, "location") == [oracle("web")["location"]]

    assert [["transportation.user_reclassify", %{"user_id" => ^id}]] =
             rows("SELECT command_type,payload FROM job_outbox")

    assert entry.worker.args_from_command(1, %{"user_id" => id}) == {:ok, %{"user_id" => id}}
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    Dawarich.Transportation.RecalculationStatus.start(id, 1, DateTime.utc_now())
    response = web(session, "text/vnd.turbo-stream.html")
    assert response.status == 200
    assert response.resp_body =~ "already running"
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
    System.delete_env("DAWARICH_RAILS")
    refute Enum.any?(Dawarich.Standalone.job_entries(), &(&1.key == entry.key))
  end

  @tag :sweep6_flash
  test "signed in login alert survives root redirect and is shown once on the map", %{id: id} do
    Repo.query!("UPDATE users SET encrypted_password=$2 WHERE id=$1", [
      id,
      "$2a$04$" <> String.duplicate("phoenixa5fixture", 4)
    ])

    session = RailsUser.session(id)
    login = browser("/users/sign_in", RailsUser.cookie(session))
    assert login.status == 302
    assert get_resp_header(login, "location") == ["http://www.example.com/"]
    root = browser("/", login.resp_cookies["_dawarich_session"].value)
    assert root.status == 302
    assert get_resp_header(root, "location") == ["http://www.example.com/map/v2"]

    cookie =
      (root.resp_cookies["_dawarich_session"] || login.resp_cookies["_dawarich_session"]).value

    map = browser("/map/v2", cookie)
    assert map.status == 200
    assert map.resp_body =~ "You are already signed in."
    second = browser("/map/v2", map.resp_cookies["_dawarich_session"].value)
    assert second.status == 200
    refute second.resp_body =~ "You are already signed in."
  end

  @tag :review_fix
  @tag review_finding: "F1"
  test "review web queued retry produces exactly one event", %{id: id} do
    Ownership.put!(Repo, "command:transportation.user_reclassify", :oban)
    prepare_user(id)
    session = RailsUser.session(id)
    assert web(session, "text/html").status == 302
    assert web(session, "text/html").status == 302

    assert rows(
             "SELECT count(*) FROM job_outbox WHERE command_type='transportation.user_reclassify' AND aggregate_id=$1",
             [id]
           ) == [[1]]

    [[event]] =
      rows("SELECT event_id FROM phoenix.transportation_recalculations WHERE user_id=$1", [id])

    event = Ecto.UUID.cast!(event)
    refute Dawarich.Transportation.RecalculationFence.claim(Repo, id, Ecto.UUID.generate())
    Dawarich.Transportation.RecalculationStatus.clear(id)
    assert web(session, "text/html").status == 302
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]

    payload = %{
      "user_id" => id,
      "event_id" => event,
      "track_ids" => [],
      "now" => DateTime.to_iso8601(DateTime.utc_now())
    }

    assert :ok = Dawarich.Transportation.AfterCommit.start(Repo, payload, Ecto.UUID.generate())
    assert rows("SELECT count(*) FROM phoenix.transportation_recalculations") == [[0]]
    assert web(session, "text/html").status == 302

    [[next]] =
      rows("SELECT event_id FROM phoenix.transportation_recalculations WHERE user_id=$1", [id])

    next = Ecto.UUID.cast!(next)
    payload = %{payload | "event_id" => next, "track_ids" => [101, 102]}
    assert :ok = Dawarich.Transportation.AfterCommit.start(Repo, payload, Ecto.UUID.generate())

    children =
      rows(
        "SELECT event_id FROM job_outbox WHERE metadata->>'parent_event_id'=$1 ORDER BY aggregate_id",
        [next]
      )

    assert length(children) == 2

    for [child] <- children do
      intent = Ecto.UUID.generate()
      progress = %{"user_id" => id, "event_id" => Ecto.UUID.cast!(child)}
      assert :ok = Dawarich.Transportation.AfterCommit.progress(Repo, progress, intent)
      assert :ok = Dawarich.Transportation.AfterCommit.progress(Repo, progress, intent)
    end

    assert rows("SELECT count(*) FROM phoenix.transportation_recalculations") == [[0]]
    assert web(session, "text/html").status == 302
  end

  @tag review_finding: "F1_failure"
  test "review failed reclassification releases its durable fence without Redis", %{id: id} do
    Ownership.put!(Repo, "command:transportation.user_reclassify", :oban)
    Ownership.put!(Repo, "command:transportation.reclassify_track", :sidekiq, pinned: true)
    prepare_user(id)
    assert web(RailsUser.session(id), "text/html").status == 302

    [[event]] =
      rows("SELECT event_id FROM phoenix.transportation_recalculations WHERE user_id=$1", [id])

    stop_supervised!(Dawarich.Redis.Cache)

    assert_raise RuntimeError, fn ->
      Dawarich.Transportation.UserReclassify.run(
        Repo,
        %{"user_id" => id, "event_id" => Ecto.UUID.cast!(event)},
        %{now: DateTime.utc_now()}
      )
    end

    assert rows("SELECT count(*) FROM phoenix.transportation_recalculations WHERE user_id=$1", [
             id
           ]) == [[0]]
  end

  @tag :review_fix
  @tag review_finding: "F2"
  test "review source ownership refusal leaves API retry eligible", %{id: id} do
    Ownership.put!(Repo, "command:users.recalculate_data", :sidekiq, pinned: true)
    assert api(%{}).status == 500
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]) == [[0]]
    Ownership.put!(Repo, "command:users.recalculate_data", :oban)
    assert Dawarich.RailsCache.get("recalculation_pending:#{id}") == :miss
    retry = api(%{})
    assert retry.status == 202
  end

  @tag :review_fix
  @tag review_finding: "F3"
  test "review valid per-form CSRF is accepted", %{id: id} do
    Ownership.put!(Repo, "command:transportation.user_reclassify", :oban)
    prepare_user(id)
    session = RailsUser.session(id)
    token = DawarichWeb.RailsCsrf.masked_form_token(session, "/tracks/recalculation", "POST")
    assert DawarichWeb.RailsCsrf.valid?(session, token, "/tracks/recalculation", "POST")
    response = review_form(session, %{"authenticity_token" => token})
    assert response.status == 302

    assert review_form(session, %{"authenticity_token" => token}, [{"x-csrf-token", "invalid"}]).status ==
             302

    assert review_form(session, %{"authenticity_token" => "invalid"}, [{"x-csrf-token", token}]).status ==
             302

    assert review_form(session, %{}).status == 422
    assert review_form(session, %{"authenticity_token" => "invalid"}).status == 422
    wrong = DawarichWeb.RailsCsrf.masked_form_token(session, "/other", "POST")
    assert review_form(session, %{"authenticity_token" => wrong}).status == 422
    wrong = DawarichWeb.RailsCsrf.masked_form_token(session, "/tracks/recalculation", "PATCH")
    assert review_form(session, %{"authenticity_token" => wrong}).status == 422
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
  end

  @tag :review_fix
  @tag review_finding: "F4"
  test "review anonymous form with valid CSRF redirects to sign in", _ctx do
    session = %{"_csrf_token" => DawarichWeb.RailsCsrf.new_token()}

    response =
      review_form(session, %{"authenticity_token" => DawarichWeb.RailsCsrf.masked_token(session)})

    assert response.status == 302
    assert get_resp_header(response, "location") == ["http://www.example.com/users/sign_in"]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
  end

  @tag :review_fix
  @tag review_finding: "F5"
  test "review web ignores untrusted target params and uses actor", %{id: id} do
    Ownership.put!(Repo, "command:transportation.user_reclassify", :oban)
    prepare_user(id)
    session = RailsUser.session(id)

    response =
      review_form(session, %{
        "authenticity_token" => DawarichWeb.RailsCsrf.masked_token(session),
        "user_id" => id + 1
      })

    assert response.status == 302
    assert [[%{"user_id" => ^id}]] = rows("SELECT payload FROM job_outbox")
  end

  @tag :review_fixture
  @tag review_finding: "F6"
  test "review web oracle contains only its isolated reclassification job", %{id: id} do
    Ownership.put!(Repo, "command:transportation.user_reclassify", :oban)
    prepare_user(id)
    assert web(RailsUser.session(id), "text/html").status == oracle("web")["status"]
    assert [["transportation.user_reclassify"]] = rows("SELECT command_type FROM job_outbox")
    assert oracle("web")["jobs"] == ["TransportationModes::UserReclassifyJob"]
  end

  defp prepare_user(id) do
    Repo.query!(
      "UPDATE users SET encrypted_password=$2 WHERE id=$1",
      [id, "$2a$04$" <> String.duplicate("phoenixa5fixture", 4)],
      log: false
    )
  end

  defp review_form(session, params, headers \\ []) do
    raw = URI.encode_query(params)

    Plug.Test.conn(:post, "/tracks/recalculation", raw)
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("accept", "text/html")
    |> then(fn conn ->
      Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)
    end)
    |> DawarichWeb.Endpoint.call([])
  end

  defp oracle(key),
    do: Jason.decode!(File.read!("test/fixtures/standalone/recalculation.json"))[key]

  defp browser(path, cookie) do
    Plug.Test.conn(:get, path)
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", cookie)
    |> put_req_header("accept", "text/html")
    |> DawarichWeb.Endpoint.call([])
  end

  defp api(params, key \\ "sweep6-synthetic") do
    raw = Jason.encode!(params)

    Plug.Test.conn(:post, "/api/v1/recalculations", raw)
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> key)
    |> DawarichWeb.Endpoint.call([])
  end

  defp web(session, accept) do
    raw = URI.encode_query(%{"authenticity_token" => DawarichWeb.RailsCsrf.masked_token(session)})

    Plug.Test.conn(:post, "/tracks/recalculation", raw)
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("accept", accept)
    |> DawarichWeb.Endpoint.call([])
  end
end
