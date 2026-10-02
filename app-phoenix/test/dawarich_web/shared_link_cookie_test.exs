defmodule DawarichWeb.SharedLinkCookieTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Dawarich.RailsCookies
  alias Dawarich.Test.A12b
  alias DawarichWeb.SharedLinkCookie

  @crypto A12b.fixture("crypto.json")

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
  end

  defp link(entry) do
    at = entry["expires_at"] && elem(DateTime.from_iso8601(entry["expires_at"]), 1)
    %{id: entry["id"], magic_phrase: entry["magic_phrase"], expires_at: at}
  end

  defp value(line),
    do: line |> String.split(";") |> hd() |> String.split("=", parts: 2) |> List.last()

  defp attributes(line),
    do:
      line
      |> String.split(";")
      |> tl()
      |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
      |> Enum.sort()

  defp with_cookie(id, value),
    do: conn(:get, "/s/#{id}") |> put_req_cookie("shared_link_#{id}", value)

  defp settings(%{"visitor_timezone" => zone}) when is_binary(zone), do: %{"timezone" => zone}
  defp settings(_entry), do: nil

  defp env(%{"time_zone_env" => zone}) when is_binary(zone), do: %{"TIME_ZONE" => zone}
  defp env(_entry), do: %{}

  defp expiry(entry),
    do: SharedLinkCookie.expires_at(link(entry), A12b.now(), settings(entry), env(entry))

  defp fallback(settings, env) do
    %{id: 1, magic_phrase: "p", expires_at: nil}
    |> SharedLinkCookie.expires_at(A12b.now(), settings, env)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  test "unlock_token is SharedLink#unlock_token, nil for a blank phrase" do
    for entry <- @crypto["shared_link"],
        do:
          assert(
            SharedLinkCookie.unlock_token(entry["id"], entry["magic_phrase"]) == entry["unlock"]
          )

    assert SharedLinkCookie.unlock_token(1, nil) == nil
    assert SharedLinkCookie.unlock_token(1, " \t ") == nil
  end

  test "reads the cookie Rails set at unlock" do
    for entry <- @crypto["shared_link"],
        do:
          assert(
            SharedLinkCookie.unlocked?(
              with_cookie(entry["id"], value(entry["set_cookie"])),
              link(entry),
              A12b.now(),
              A12b.secret()
            )
          )
  end

  test "writes the cookie with Rails' attributes, expiry and value" do
    for entry <- @crypto["shared_link"] do
      conn =
        conn(:post, "http://dawarich.example/s/#{entry["id"]}/unlock")
        |> SharedLinkCookie.put(link(entry), expiry(entry), A12b.secret())
        |> send_resp(302, "")

      [line] =
        for l <- get_resp_header(conn, "set-cookie"),
            String.starts_with?(l, "shared_link_#{entry["id"]}="),
            do: l

      assert attributes(line) == attributes(entry["set_cookie"])

      assert RailsCookies.decrypt(
               value(line),
               "shared_link_#{entry["id"]}",
               A12b.secret(),
               A12b.now()
             ) == {:ok, entry["unlock"]}
    end
  end

  test "refuses an expired, foreign, tampered or missing cookie; a link without a phrase is always unlocked" do
    [entry | _] = @crypto["shared_link"]

    expired =
      RailsCookies.encrypt(
        entry["unlock"],
        "shared_link_#{entry["id"]}",
        A12b.secret(),
        DateTime.add(A12b.now(), -1)
      )

    foreign =
      RailsCookies.encrypt(
        entry["unlock"],
        "shared_link_1",
        A12b.secret(),
        DateTime.add(A12b.now(), 60)
      )

    wrong =
      RailsCookies.encrypt(
        "other",
        "shared_link_#{entry["id"]}",
        A12b.secret(),
        DateTime.add(A12b.now(), 60)
      )

    for value <- [expired, foreign, wrong, "garbage"],
        do:
          refute(
            SharedLinkCookie.unlocked?(
              with_cookie(entry["id"], value),
              link(entry),
              A12b.now(),
              A12b.secret()
            )
          )

    refute SharedLinkCookie.unlocked?(conn(:get, "/s/1"), link(entry), A12b.now(), A12b.secret())

    assert SharedLinkCookie.unlocked?(
             conn(:get, "/s/1"),
             %{link(entry) | magic_phrase: ""},
             A12b.now(),
             A12b.secret()
           )
  end

  test "property: put then unlocked? round-trips for any id and phrase until the expiry" do
    A12b.seeded(fn n ->
      link = %{
        id: n,
        magic_phrase: "p " <> A12b.text(),
        expires_at: DateTime.add(A12b.now(), 3600)
      }

      at = SharedLinkCookie.expires_at(link, A12b.now(), nil, %{})
      conn = conn(:post, "/s/#{n}/unlock") |> SharedLinkCookie.put(link, at, A12b.secret())

      cookie = conn.resp_cookies["shared_link_#{n}"].value
      assert SharedLinkCookie.unlocked?(with_cookie(n, cookie), link, A12b.now(), A12b.secret())

      refute SharedLinkCookie.unlocked?(
               with_cookie(n, cookie),
               link,
               DateTime.add(A12b.now(), 3600),
               A12b.secret()
             )
    end)
  end

  test "the 30-day fallback follows the visitor's zone, then the app zone, never the process environment" do
    assert fallback(nil, %{}) == "2026-11-01T13:00:00Z"
    assert fallback(nil, %{"TIME_ZONE" => "UTC"}) == "2026-11-01T12:00:00Z"
    assert fallback(nil, %{"TIME_ZONE" => "Berlin"}) == "2026-11-01T13:00:00Z"
    assert fallback(%{"timezone" => "Asia/Tokyo"}, %{}) == "2026-11-01T12:00:00Z"

    assert fallback(%{"timezone" => "Asia/Tokyo"}, %{"TIME_ZONE" => "Europe/Berlin"}) ==
             "2026-11-01T12:00:00Z"

    assert fallback(%{"timezone" => ""}, %{}) == "2026-11-01T13:00:00Z"
    assert fallback(%{}, %{}) == "2026-11-01T12:00:00Z"
    assert fallback(%{}, %{"TIME_ZONE" => "Europe/Berlin"}) == "2026-11-01T13:00:00Z"

    link = %{id: 1, magic_phrase: "p", expires_at: ~N[2026-10-05 12:00:00]}
    assert SharedLinkCookie.expires_at(link, A12b.now(), nil, %{}) == ~U[2026-10-05 12:00:00Z]
  end

  test "marks the cookie secure when the request is https, as Rails' request.ssl? does" do
    [entry | _] = @crypto["shared_link"]

    for url <- [
          "https://dawarich.example/s/#{entry["id"]}/unlock",
          "http://dawarich.example/s/#{entry["id"]}/unlock"
        ] do
      conn =
        conn(:post, url)
        |> SharedLinkCookie.put(link(entry), expiry(entry), A12b.secret())
        |> send_resp(302, "")

      [line] = get_resp_header(conn, "set-cookie")
      assert "secure" in attributes(line) == String.starts_with?(url, "https:"), url
    end
  end
end
