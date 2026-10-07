defmodule DawarichWeb.A12f3bA01Test do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{AchievementPageGate, RailsAuth, RailsCsrf}
  alias DawarichWeb.AchievementActions.{Request, Unlocks, Sharing}

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    RailsUser.insert!(%{
      id: 81301,
      email: "achievement-refusals@example.invalid",
      settings: %{"locale" => "en", "timezone" => "Europe/Berlin"}
    })

    rows(
      "INSERT INTO achievement_unlock_events(user_id,kind,key,created_at,updated_at) VALUES(81301,'geography','FR',now(),now())"
    )

    :ok
  end

  @tag a12f3b_case: "A01a"
  test "achievement pages and unlock writes own malformed source states" do
    session = RailsUser.session(81301)

    guest =
      build_conn("POST", "/achievements/unlocks/next", "{}")
      |> put_req_header("accept", "application/json")

    assert Unlocks.call(guest, []).status == 401

    for {action, path, body} <- [
          {:next, "/achievements/unlocks/next", "{}"},
          {:seen, "/achievements/unlocks/1/seen", ~s({"claim_token":"wrong"})},
          {:dismiss, "/achievements/unlocks/dismiss", ~s({"batch_end_id":1})}
        ] do
      conn = request(path, body, session) |> put_req_header("x-csrf-token", "invalid")
      assert Unlocks.call(conn, action: action).status == 422

      assert rows(
               "SELECT claim_token,claimed_at,seen_at FROM achievement_unlock_events WHERE user_id=81301"
             ) == [[nil, nil, nil]]
    end

    assert Unlocks.call(request("/achievements/unlocks/dismiss", "{}", session), []).status == 400

    assert DawarichWeb.Endpoint.call(
             request("/achievements/unlocks/next", "{}", session),
             DawarichWeb.Endpoint.init([])
           ).status == 200

    rows(
      "UPDATE achievement_unlock_events SET claim_token=NULL,claimed_at=NULL WHERE user_id=81301"
    )

    for {path, status} <- [
          {"/achievements/country_fr", 302},
          {"/achievements/missing", 404},
          {"/achievements/border_hopper", 302}
        ] do
      page =
        build_conn("GET", path)
        |> put_req_header("accept", "text/html")
        |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))

      assert DawarichWeb.Endpoint.call(page, DawarichWeb.Endpoint.init([])).status == status
    end

    conn =
      build_conn("GET", "/achievements")
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> RailsAuth.call([])

    assert AchievementPageGate.open?(conn, %{})
    rows("UPDATE users SET encrypted_password='revoked' WHERE id=81301")
    refute AchievementPageGate.open?(conn, %{})
  end

  @tag a12f3b_case: "A01b"
  test "achievement connected event reloads changed access" do
    session = RailsUser.session(81301)

    for change <- ["locked_at=now()", "deleted_at=now()", "encrypted_password='revoked'"] do
      for {action, path, body, plug} <- [
            {:next, "/achievements/unlocks/next", "{}", Unlocks},
            {:seen, "/achievements/unlocks/1/seen", ~s({"claim_token":"wrong"}), Unlocks},
            {:sharing, "/achievements/country_de/toggle_sharing", "{}", Sharing}
          ] do
        conn = request(path, body, session)
        {:ok, conn, actor, params, context} = Request.load(conn, action)
        admitted = assign(conn, :achievement_action, {actor, params, context})
        rows("UPDATE users SET #{change} WHERE id=81301")

        socket = %Phoenix.LiveView.Socket{
          assigns: %{
            __changed__: %{},
            current_user: actor,
            locale: "en",
            achievement_initial: false
          }
        }

        assert {:noreply, %{redirected: {:redirect, %{to: "/users/sign_in"}}}} =
                 DawarichWeb.AchievementsLive.handle_params(%{}, "", socket)

        assert plug.call(admitted, []).status == 401

        assert rows(
                 "SELECT claim_token,claimed_at,seen_at FROM achievement_unlock_events WHERE user_id=81301"
               ) == [[nil, nil, nil]]

        assert rows("SELECT count(*) FROM achievement_progresses WHERE user_id=81301") == [[0]]

        rows(
          "UPDATE users SET locked_at=NULL,deleted_at=NULL,encrypted_password=$1 WHERE id=81301",
          [actor.encrypted_password]
        )
      end
    end
  end

  defp request(path, body, session) do
    method = if String.ends_with?(path, "toggle_sharing"), do: "PATCH", else: "POST"

    build_conn(method, path, body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-csrf-token", RailsCsrf.masked_form_token(session, path, method))
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
  end
end
