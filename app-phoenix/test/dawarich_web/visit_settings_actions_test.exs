defmodule DawarichWeb.VisitSettingsActionsTest do
  use Dawarich.IngestCase
  import Dawarich.Test.RailsFormRequests
  import Plug.Conn
  alias Dawarich.ScratchRepo
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  setup do
    Dawarich.JobsCase.reset!(ScratchRepo)

    actor =
      RailsUser.insert!(%{
        id: 8895,
        visits_redetected_at: nil,
        email: "a8-settings-actions@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin", "visit_min_points" => 3, "unrelated" => "kept"}
      })

    ScratchRepo.insert_all("users", [actor])
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :jobs_repo, previous),
        else: Application.delete_env(:dawarich, :jobs_repo)
    end)

    session = RailsUser.session(actor.id)
    %{session: session, token: RailsCsrf.masked_token(session), user: actor}
  end

  test "settings native verbs and POST override redirect with Rails notice", ctx do
    for method <- [:patch, :put, :post] do
      params = %{"settings" => %{"visit_radius_meters" => "75"}}
      params = if method == :post, do: Map.put(params, "_method", "patch"), else: params
      body = Plug.Conn.Query.encode(params)
      conn = request(ctx, method, "/settings/visits", body)
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://www.example.com/settings/visits"]

      assert rails_session(conn)["flash"]["flashes"]["notice"] ==
               "Visit detection settings updated"

      assert [[%{"visit_radius_meters" => 75, "visit_min_points" => 3, "unrelated" => "kept"}]] =
               ScratchRepo.query!("SELECT settings FROM users WHERE id=$1", [ctx.user.id]).rows
    end
  end

  test "redetection redirects after queue but hands cooldown back before effects", ctx do
    body = ""
    conn = request(ctx, :post, "/visits/redetections", body)
    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["http://www.example.com/settings/visits"]

    assert rails_session(conn)["flash"]["flashes"]["notice"] ==
             "Re-detection queued. We'll notify you when it finishes."

    assert [
             [
               "visits.web_redetect",
               %{"user_id" => 8895, "locale" => "en", "timezone" => "Europe/Berlin"}
             ]
           ] =
             ScratchRepo.query!("SELECT kind,payload FROM phoenix.rails_commands").rows

    ScratchRepo.query!("UPDATE users SET visits_redetected_at=$1 WHERE id=$2", [
      DateTime.utc_now() |> DateTime.to_naive(),
      ctx.user.id
    ])

    upstream = upstream!()

    {{line, forwarded}, conn} =
      forwarded(upstream, fn -> request(ctx, :post, "/visits/redetections", body) end)

    assert line == "POST /visits/redetections HTTP/1.1"
    assert forwarded == body
    assert conn.status == 204
    assert ScratchRepo.query!("SELECT count(*) FROM phoenix.rails_commands").rows == [[1]]
  end

  defp request(ctx, method, path, body) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
    |> put_req_header("accept", "text/html")
    |> put_req_header("x-csrf-token", ctx.token)
    |> put_req_header("content-type", "application/x-www-form-urlencoded;charset=UTF-8")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> Phoenix.ConnTest.dispatch(DawarichWeb.Endpoint, method, path, body)
  end
end
