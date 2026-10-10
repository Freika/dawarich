defmodule DawarichWeb.VisitActionsTest do
  use Dawarich.JobsCase

  import Plug.Conn
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.{Repo, ScratchRepo}
  alias Dawarich.Test.{ParityHTML, RailsUser}
  alias Dawarich.Visits.{WebUpdate, WebDelete, WebBulk, WebMerge}
  alias DawarichWeb.{RailsCsrf, VisitStreams}

  @tables ~w(places areas tags visits place_visits tracks track_segments points stats taggings notes)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    Dawarich.FixtureCleanup.delete!(
      ScratchRepo,
      ~w(places tags taggings visits place_visits areas notes tracks track_segments)
    )

    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)
    :ok
  end

  defp fixture(name) do
    state = File.read!("test/fixtures/a8vv/visits/#{name}.json") |> Jason.decode!()
    u = hd(state["before"]["users"])

    attrs = %{
      id: u["id"],
      email: u["email"],
      settings: u["settings"],
      api_key: u["api_key"],
      plan: u["plan"],
      visits_redetected_at: NaiveDateTime.from_iso8601!(u["visits_redetected_at"])
    }

    actor = RailsUser.insert!(attrs)
    ScratchRepo.insert_all("users", [actor])

    for table <- @tables, row <- Map.get(state["before"]["rows"], table, []) do
      ScratchRepo.query!(
        "INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table}, $1::text::json)",
        [Jason.encode!(row)]
      )
    end

    {:ok, now, _} = DateTime.from_iso8601(state["now"])
    user = Dawarich.Accounts.get(actor.id)
    session = RailsUser.session(actor.id)

    %{
      user: user,
      now: now,
      self_hosted: state["self_hosted"],
      repo: ScratchRepo,
      locale: "en",
      csrf: "CSRF",
      state: state,
      session: session,
      token: RailsCsrf.masked_token(session)
    }
  end

  defp change(action, ctx) do
    params = ctx.state["request"]["params"]
    id = ctx.state["request"]["path"] |> String.split("/") |> List.last()

    case action do
      :update -> WebUpdate.run(ScratchRepo, ctx.user, id, params["visit"], ctx)
      :destroy -> WebDelete.run(ScratchRepo, ctx.user, id, params, ctx)
      :bulk_update -> WebBulk.run(ScratchRepo, :update, ctx.user, params, ctx)
      :bulk_destroy -> WebBulk.run(ScratchRepo, :destroy, ctx.user, params, ctx)
      :merge -> WebMerge.run(ScratchRepo, ctx.user, params["visit_ids"], ctx)
    end
  end

  defp streams(html) do
    tree = LazyHTML.from_fragment(html) |> LazyHTML.query("turbo-stream")
    Enum.zip(LazyHTML.attribute(tree, "action"), LazyHTML.attribute(tree, "target"))
  end

  defp render(action, result, ctx),
    do:
      VisitStreams.render(
        action,
        result,
        Map.take(ctx, [:user, :now, :self_hosted, :repo, :locale, :csrf])
      )

  defp parity(html, name),
    do:
      assert(
        ParityHTML.normalize(html) ==
          ParityHTML.normalize(File.read!("test/fixtures/a8vv/visits/#{name}.html"))
      )

  @tag :safe_back3
  test "F3 visit update uses Rails timeline fallback and preserves same-host returns" do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    ctx = fixture("rename")
    body = "_method=patch&visit%5Bname%5D=Renamed"

    for {referer, location} <- [
          {"https://outside.example/map",
           "http://www.example.com/map/v2?date=today&panel=timeline&status=suggested"},
          {"http://user@www.example.com/map",
           "http://www.example.com/map/v2?date=today&panel=timeline&status=suggested"},
          {"/map/v2?date=2026-10-03#timeline",
           "http://www.example.com/map/v2?date=2026-10-03#timeline"},
          {"https://www.example.com:8443/map/v2", "https://www.example.com:8443/map/v2"}
        ] do
      response =
        post_form(
          ctx.session,
          body,
          [{"accept", "text/html"}, {"x-csrf-token", ctx.token}, {"referer", referer}],
          ctx.state["request"]["path"]
        )

      assert response.status == 302
      assert get_resp_header(response, "location") == [location]
      assert rows("SELECT name FROM visits WHERE id=902000") == [["Renamed"]]
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    end
  end

  test "single edit replaces the row calendar and notice in Rails order" do
    ctx = fixture("rename")
    assert {:ok, result} = change(:update, ctx)
    html = render(:update, result, ctx)

    assert streams(html) == [
             {"replace", "visit_entry_902000"},
             {"replace", "timeline-calendar-frame"},
             {"append", "flash-messages"}
           ]

    parity(html, "rename")
  end

  test "destroy removes only the row and refreshes its calendar" do
    ctx = fixture("soft_delete_turbo")
    assert {:ok, result} = change(:destroy, ctx)
    html = render(:destroy, result, ctx)

    assert streams(html) == [
             {"remove", "visit_entry_925000"},
             {"replace", "timeline-calendar-frame"},
             {"append", "flash-messages"}
           ]

    parity(html, "soft_delete_turbo")
  end

  test "bulk update replaces frame children without nesting a frame" do
    ctx = fixture("bulk_date")
    assert {:ok, result} = change(:bulk_update, ctx)
    html = render(:bulk_update, result, ctx)

    assert streams(html) == [
             {"update", "timeline-feed-frame"},
             {"replace", "timeline-calendar-frame"},
             {"append", "flash-messages"}
           ]

    refute html =~ "<turbo-frame id=\"timeline-feed-frame\""

    parity(html, "bulk_date")
  end

  test "cross-day bulk deletion does not overwrite an unrelated day" do
    ctx = fixture("bulk_cross_day_destroy")
    assert {:ok, result} = change(:bulk_destroy, ctx)
    html = render(:bulk_destroy, result, ctx)
    assert streams(html) == [{"replace", "timeline-calendar-frame"}, {"append", "flash-messages"}]
    parity(html, "bulk_cross_day_destroy")
  end

  test "merge emits exactly feed update then notice using latest rows" do
    ctx = fixture("merge_points")
    assert {:ok, result} = change(:merge, ctx)
    html = render(:merge, result, ctx)
    assert streams(html) == [{"update", "timeline-feed-frame"}, {"append", "flash-messages"}]

    assert length(Regex.scan(~r/id="visit_entry_\d+"/, html)) == 1

    parity(html, "merge_points")
  end

  @tag :endpoint
  test "HTML referer redirect uses Rails fallback and flash status" do
    assert Code.ensure_loaded?(DawarichWeb.VisitActions)
    ctx = fixture("soft_delete")
    body = "_method=delete"

    conn =
      post_form(
        ctx.session,
        body,
        [{"accept", "text/html"}, {"x-csrf-token", ctx.token}],
        ctx.state["request"]["path"]
      )

    assert conn.status == 303

    assert get_resp_header(conn, "location") == [
             "http://www.example.com/map/v2?date=today&panel=timeline"
           ]

    refute Map.has_key?(conn.resp_cookies, "_dawarich_session")

    edit = fixture("rename")
    body = "_method=patch&visit%5Bname%5D=Renamed"
    headers = [{"accept", "text/html"}, {"x-csrf-token", edit.token}]
    path = edit.state["request"]["path"]
    back = "http://www.example.com/map/v2?date=2026-10-03&panel=timeline"
    conn = post_form(edit.session, body, [{"referer", back} | headers], path)
    assert conn.status == 302
    assert get_resp_header(conn, "location") == [back]

    conn = post_form(edit.session, body, headers, path)

    assert get_resp_header(conn, "location") ==
             ["http://www.example.com/map/v2?date=today&panel=timeline&status=suggested"]

    conn =
      post_form(edit.session, body, [{"referer", "https://outside.example/map"} | headers], path)

    assert conn.status == 302

    assert get_resp_header(conn, "location") == [
             "http://www.example.com/map/v2?date=today&panel=timeline&status=suggested"
           ]

    assert rows("SELECT name FROM visits WHERE id=902000") == [["Renamed"]]
  end

  test "post-write render reads the same repository as the owning transaction" do
    ctx = fixture("rename")

    assert Repo.query!("SELECT count(*) FROM visits WHERE user_id=$1", [ctx.user.id]).rows == [
             [0]
           ]

    assert {:ok, result} = change(:update, ctx)
    html = render(:update, result, ctx)
    assert html =~ "Renamed"

    assert length(Regex.scan(~r/id="visit_entry_902000"/, html)) == 1

    parity(html, "rename")
  end
end
