defmodule DawarichWeb.RailsSessionIdentityTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Dawarich.{RailsCookies, RailsSecret}
  alias DawarichWeb.{LayoutAssigns, Locale, RailsAuth, RailsSession, RequireUser}

  @fixture "test/fixtures/rails_session_writer.json" |> File.read!() |> Jason.decode!()
  @alert "You need to sign in or sign up before continuing."

  defp decrypt(conn) do
    {:ok, session} =
      RailsCookies.decrypt(
        conn.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        RailsSecret.fetch(),
        DateTime.utc_now()
      )

    session
  end

  defp guest do
    conn(:get, "http://127.0.0.1/stats?locale=en")
    |> fetch_query_params()
    |> RailsAuth.call([])
    |> Locale.call([])
    |> LayoutAssigns.call([])
    |> RequireUser.call([])
  end

  @tag :fresh_identity
  test "a fresh guest commit supplies a Rails session identity with its alert and return path" do
    first = guest()
    session = decrypt(first)
    another = guest() |> decrypt()
    valid = Regex.match?(~r/\A[0-9a-f]{32}\z/, session["session_id"] || "")
    distinct = session["session_id"] != another["session_id"]
    alert_matches = get_in(session, ["flash", "flashes", "alert"]) == @alert
    csrf_present = is_binary(session["_csrf_token"])

    cookie_count =
      Enum.count(
        get_resp_header(first, "set-cookie"),
        &String.starts_with?(&1, "_dawarich_session=")
      )

    assert first.status == 302
    assert valid
    assert distinct
    assert alert_matches
    assert csrf_present
    assert session["user_return_to"] == "/stats?locale=en"
    assert session["locale"] == "en"
    assert cookie_count == 1
  end

  @tag :existing_identity
  test "a staged commit preserves the existing Rails session identity and every untouched field" do
    cookie = @fixture["session_cookie"]

    {:ok, original} =
      RailsCookies.decrypt(cookie, "_dawarich_session", RailsSecret.fetch(), DateTime.utc_now())

    committed =
      conn(:get, "http://127.0.0.1/stats")
      |> put_req_cookie("_dawarich_session", cookie)
      |> RailsSession.stage(%{"locale" => "ca"})
      |> RailsSession.stage(%{"user_return_to" => "/stats"})
      |> send_resp(200, "")
      |> decrypt()

    original_identity_present = is_binary(original["session_id"])
    identity_preserved = committed["session_id"] == original["session_id"]

    untouched_preserved =
      Map.drop(committed, ["locale", "user_return_to"]) ==
        Map.drop(original, ["locale", "user_return_to"])

    assert original_identity_present
    assert identity_preserved
    assert untouched_preserved
    assert committed["locale"] == "ca"
    assert committed["user_return_to"] == "/stats"
  end
end
