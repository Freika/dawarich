defmodule DawarichWeb.AchievementAuthRefusalTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{AuthHandler, Endpoint, RailsCsrf}
  alias DawarichWeb.AchievementActions.{Request, Sharing, Unlocks}

  setup do
    previous = Map.take(System.get_env(), ~w(DAWARICH_RAILS SELF_HOSTED))
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true"})
    id = "achievement-auth-refusal-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(id, [:dawarich, :standalone, :handback], &__MODULE__.event/4, self())

    on_exit(fn ->
      :telemetry.detach(id)

      for key <- ~w(DAWARICH_RAILS SELF_HOSTED) do
        if previous[key], do: System.put_env(key, previous[key]), else: System.delete_env(key)
      end
    end)

    RailsUser.insert!(%{id: 81401, email: "achievement-auth-refusal@example.invalid"})
    %{session: RailsUser.session(81401)}
  end

  test "signed-out POST /achievements/unlocks/next in standalone returns Rails 401 body and zero hand-back telemetry",
       %{session: session} do
    logout =
      request("DELETE", "/users/sign_out", session, "application/x-www-form-urlencoded", "")
      |> put_req_header("accept", "text/html")
      |> AuthHandler.call(enabled: true, native: true, registration_enabled: false)

    assert logout.status == 303
    cookie = logout.resp_cookies["_dawarich_session"].value

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        for {method, path} <- [
              {"POST", "/achievements/unlocks/next"},
              {"POST", "/achievements/unlocks/1/seen"},
              {"POST", "/achievements/unlocks/dismiss"},
              {"PATCH", "/achievements/country_de/toggle_sharing"}
            ] do
          conn =
            request(method, path, session)
            |> Plug.Test.put_req_cookie("_dawarich_session", cookie)
            |> Endpoint.call([])

          refute_received {:handback, _}
          assert conn.status == 401

          assert conn.resp_body ==
                   ~s({"error":"You need to sign in or sign up before continuing."})

          assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
          assert conn.halted
        end

        for {method, path, body} <- [
              {"POST", "/trips", "trip[name]=synthetic"},
              {"POST", "/places", "place[name]=synthetic"},
              {"POST", "/route_videos", "route_video[file]=synthetic"},
              {"POST", "/visits/merge", "visit_ids[]=1"}
            ] do
          conn =
            request(method, path, session, "application/x-www-form-urlencoded", body)
            |> put_req_header("accept", "text/html")
            |> Plug.Test.put_req_cookie("_dawarich_session", cookie)
            |> Endpoint.call([])

          refute_received {:handback, _}
          assert conn.status == 302
          assert conn.resp_body == ""
          assert get_resp_header(conn, "location") == ["http://www.example.com/users/sign_in"]
        end

        for {action, method, path, plug} <- [
              {:next, "POST", "/achievements/unlocks/next", Unlocks},
              {:sharing, "PATCH", "/achievements/country_de/toggle_sharing", Sharing}
            ] do
          conn = request(method, path, session)
          {:ok, conn, actor, params, context} = Request.load(conn, action)
          conn = assign(conn, :achievement_action, {actor, params, context})
          Repo.query!("UPDATE users SET locked_at=now() WHERE id=$1", [actor.id])
          refused = plug.call(conn, [])
          refute_received {:handback, _}
          assert refused.status == 401
          assert refused.resp_body == ~s({"error":"Your account is locked."})
          Repo.query!("UPDATE users SET locked_at=NULL WHERE id=$1", [actor.id])
        end
      end)

    refute log =~ "[standalone.handback]"

    unsupported =
      request("POST", "/achievements/unlocks/next", session)
      |> put_req_header("x-csrf-token", "invalid")
      |> Endpoint.call([])

    assert unsupported.status == 422
    assert_received {:handback, %{reason: "achievement_request", status: 422}}

    marked =
      request("POST", "/achievements/unlocks/next", Map.put(session, "client", "ios"))
      |> Endpoint.call([])

    assert marked.status == 401
    assert_received {:handback, %{reason: "achievement_request", status: 401}}
  end

  def event(_event, _measurements, metadata, pid), do: send(pid, {:handback, metadata})

  defp request(method, path, session, type \\ "application/json", body \\ "{}") do
    Phoenix.ConnTest.build_conn(method, path, body)
    |> put_req_header("content-type", type)
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-csrf-token", RailsCsrf.masked_form_token(session, path, method))
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
  end
end
