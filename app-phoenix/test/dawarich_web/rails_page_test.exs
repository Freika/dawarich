defmodule DawarichWeb.RailsPageTest do
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2, put_req_header: 3]

  alias Dawarich.{RailsCookies, RailsSecret, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{RailsCsrf, Translate}

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    %{user: RailsUser.insert!(%{id: 4201, email: "a5-page@dawarich.test"})}
  end

  def count_query(_event, _measurements, %{query: query}, pid), do: send(pid, {:query, query})

  defp flush do
    receive do
      message -> [message | flush()]
    after
      0 -> []
    end
  end

  defp rails_session(conn) do
    %{value: value} = conn.resp_cookies["_dawarich_session"]

    {:ok, session} =
      RailsCookies.decrypt(value, "_dawarich_session", RailsSecret.fetch(), DateTime.utc_now())

    session
  end

  defp with_session(session),
    do: build_conn() |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))

  defp settings(user),
    do: Repo.one(from(u in "users", where: u.id == ^user.id, select: u.settings))

  test "a page view looks the Rails user up once", %{user: user} do
    returning = RailsUser.signed_in(user.id) |> get("/notifications") |> recycle()
    assert Map.has_key?(Plug.Conn.fetch_cookies(returning).req_cookies, "_dawarich_phoenix")
    :telemetry.attach("a5-users", [:dawarich, :repo, :query], &__MODULE__.count_query/4, self())
    on_exit(fn -> :telemetry.detach("a5-users") end)

    get(returning, "/notifications")

    assert length(for({:query, query} <- flush(), query =~ ~s(FROM "public"."users"), do: query)) ==
             1
  end

  test "a signed-out visitor goes to sign in with Devise's alert and the way back" do
    conn = get(build_conn(), "/notifications?page=2&locale=de")

    assert redirected_to(conn, 302) == "http://www.example.com/users/sign_in"
    session = rails_session(conn)

    assert session["flash"] == %{
             "discard" => [],
             "flashes" => %{"alert" => Translate.t("de", "devise.failure.unauthenticated", %{})}
           }

    assert session["user_return_to"] == "/notifications?page=2&locale=de"
    assert session["locale"] == "de"
  end

  test "a locked account goes to sign in with Devise's locked alert, signed out of Rails",
       %{user: user} do
    Repo.update_all(from(u in "users", where: u.id == ^user.id),
      set: [locked_at: NaiveDateTime.utc_now()]
    )

    conn = get(RailsUser.signed_in(user.id), "/notifications")

    assert redirected_to(conn, 302) == "http://www.example.com/users/sign_in"
    session = rails_session(conn)
    assert Translate.t("en", "devise.failure.locked", %{}) == "Your account is locked."

    assert session["flash"]["flashes"] == %{
             "alert" => Translate.t("en", "devise.failure.locked", %{})
           }

    refute Map.has_key?(session, "warden.user.user.key")
    assert session["user_return_to"] == "/notifications"
  end

  test "every Rails session decision of one request lands in one cookie" do
    stale = RailsUser.cookie(%{"flash" => %{"discard" => [], "flashes" => %{"notice" => "old"}}})

    conn =
      build_conn()
      |> put_req_cookie("_dawarich_session", stale)
      |> get("/notifications?locale=de")

    assert length(
             for(
               "_dawarich_session=" <> _ = line <- get_resp_header(conn, "set-cookie"),
               do: line
             )
           ) == 1

    session = rails_session(conn)

    assert session["flash"] == %{
             "discard" => [],
             "flashes" => %{"alert" => Translate.t("de", "devise.failure.unauthenticated", %{})}
           }

    assert session["user_return_to"] == "/notifications?locale=de"
    assert session["locale"] == "de"
    assert is_binary(session["_csrf_token"])
  end

  test "a Rails flash is shown once, without its discarded keys, and consumed", %{user: user} do
    flash = %{
      "discard" => ["alert"],
      "flashes" => %{"notice" => "Saved & done", "alert" => "stale"}
    }

    conn = get(with_session(RailsUser.session(user.id, %{"flash" => flash})), "/notifications")

    body = html_response(conn, 200)
    assert body =~ "Saved &amp; done"
    refute body =~ "stale"
    refute Map.has_key?(rails_session(conn), "flash")
  end

  test "a 404 leaves the Rails session alone, flash and locale included, as Rails' exception does",
       %{user: user} do
    flash = %{"discard" => [], "flashes" => %{"notice" => "Saved"}}
    session = user.id |> RailsUser.session(%{"flash" => flash}) |> Map.delete("_csrf_token")

    {404, headers, _body} =
      assert_error_sent(404, fn -> get(with_session(session), "/notifications/999?locale=de") end)

    refute Enum.any?(headers, fn {name, value} ->
             name == "set-cookie" and String.starts_with?(value, "_dawarich_session=")
           end)
  end

  test "a session without a CSRF token gets one that Rails accepts", %{user: user} do
    conn =
      get(with_session(Map.delete(RailsUser.session(user.id), "_csrf_token")), "/notifications")

    [_, token] = Regex.run(~r/name="csrf-token"\s+content="([^"]+)"/, html_response(conn, 200))
    assert RailsCsrf.valid?(rails_session(conn), token)
  end

  test "a page view with nothing to consume or create writes no Rails cookie", %{user: user} do
    conn = get(RailsUser.signed_in(user.id), "/notifications")
    refute Map.has_key?(conn.resp_cookies, "_dawarich_session")
  end

  test "a locale the reader chose is remembered in the session and on the user", %{user: user} do
    conn = get(RailsUser.signed_in(user.id), "/notifications?locale=DE")

    assert html_response(conn, 200) =~ ~s(<html lang="de")
    assert rails_session(conn)["locale"] == "de"
    assert settings(user)["locale"] == "de"
  end

  test "a cross-site or prefetch request shows the locale without remembering it", %{user: user} do
    for {name, value} <- [
          {"sec-fetch-site", "cross-site"},
          {"sec-purpose", "prefetch"},
          {"x-moz", "PREFETCH"}
        ] do
      conn =
        RailsUser.signed_in(user.id)
        |> put_req_header(name, value)
        |> get("/notifications?locale=de")

      assert html_response(conn, 200) =~ ~s(<html lang="de")
      refute Map.has_key?(conn.resp_cookies, "_dawarich_session")
    end

    assert settings(user) == %{}
  end

  test "a reader whose browser prefers another language is offered it", %{user: user} do
    conn =
      RailsUser.signed_in(user.id)
      |> put_req_header("accept-language", "de")
      |> get("/notifications")

    assert html_response(conn, 200) =~ ~s(href="/notifications?locale=de")
  end

  test "the offered language keeps list and nested query params as Rails writes them", %{
    user: user
  } do
    conn =
      RailsUser.signed_in(user.id)
      |> put_req_header("accept-language", "de")
      |> get("/notifications?x[]=1&y[b]=2")

    assert html_response(conn, 200) =~
             ~s(href="/notifications?locale=de&amp;x%5B%5D=1&amp;y%5Bb%5D=2")
  end

  test "a Turbo fetch from a Rails page gets a reload stub and changes nothing", %{user: user} do
    flash = %{"discard" => [], "flashes" => %{"notice" => "kept"}}

    conn =
      with_session(RailsUser.session(user.id, %{"flash" => flash}))
      |> put_req_header("x-turbo-request-id", "1")
      |> get("/notifications")

    assert html_response(conn, 200) =~ ~s(<meta name="turbo-visit-control" content="reload">)
    assert conn.resp_cookies == %{}
  end
end
