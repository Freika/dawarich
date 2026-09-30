defmodule DawarichWeb.Api.RespondTest do
  use Dawarich.IngestCase, async: false
  import Plug.Test
  import Plug.Conn

  alias Dawarich.Accounts
  alias DawarichWeb.Api.{Auth, Respond}

  @key "phoenix-a4g2-key-respond"
  @term {:object, [{"k", "v"}]}

  setup do
    %{
      id:
        user!(%{
          api_key: @key,
          settings: %{"maps" => %{"distance_unit" => "mi"}, "timezone" => "UTC"}
        })
    }
  end

  defp authed(headers \\ []) do
    conn(:get, "/api/v1/insights")
    |> Map.update!(
      :req_headers,
      &(&1 ++ [{"authorization", "Bearer #{@key}"}, {"accept", "application/json"} | headers])
    )
    |> assign(:api_params, %{})
    |> assign(:api_tag, "api")
    |> put_private(:dawarich_raw_body, "")
    |> Auth.call(require_active: false)
  end

  defp header(conn, name), do: conn |> get_resp_header(name) |> List.first()

  test "cache_control: replaces Rails' default next to the Rack ETag, and the If-None-Match 304 keeps it" do
    sent = Respond.json(authed(), 200, @term, cache_control: "max-age=300, private")
    assert {200, "max-age=300, private"} == {sent.status, header(sent, "cache-control")}
    etag = header(sent, "etag")
    assert etag =~ ~r|\AW/"[0-9a-f]{32}"\z|

    again =
      Respond.json(authed([{"if-none-match", etag}]), 200, @term,
        cache_control: "max-age=300, private"
      )

    assert {304, "", etag, "max-age=300, private", nil} ==
             {again.status, again.resp_body, header(again, "etag"),
              header(again, "cache-control"), header(again, "content-type")}
  end

  test "last_modified: sets Last-Modified and the given Cache-Control, and no ETag, so If-None-Match never matches" do
    stamp = "Sun, 06 Nov 1994 08:49:37 GMT"

    sent =
      Respond.json(authed(), 200, @term,
        cache_control: "max-age=3600, private",
        last_modified: stamp
      )

    assert {200, stamp, "max-age=3600, private", nil} ==
             {sent.status, header(sent, "last-modified"), header(sent, "cache-control"),
              header(sent, "etag")}

    assert Respond.json(authed([{"if-none-match", ~s(W/"x")}]), 200, @term,
             cache_control: "max-age=3600, private",
             last_modified: stamp
           ).status == 200
  end

  test "not_modified answers stale?'s 304: Last-Modified, the default Cache-Control, no Content-Type, no Vary, no body" do
    sent = Respond.not_modified(authed(), "Sun, 06 Nov 1994 08:49:37 GMT")
    assert {304, ""} == {sent.status, sent.resp_body}

    assert {"Sun, 06 Nov 1994 08:49:37 GMT", "max-age=0, private, must-revalidate", nil, nil, nil} ==
             {header(sent, "last-modified"), header(sent, "cache-control"),
              header(sent, "content-type"), header(sent, "vary"), header(sent, "etag")}

    assert header(sent, "x-dawarich-response") == "Hey, I'm alive and authenticated!"
  end

  test "json/3 is unchanged: the Rack ETag with max-age=0, private, must-revalidate; a 404 gets no-cache" do
    sent = Respond.json(authed(), 200, @term)

    assert {"max-age=0, private, must-revalidate", true} ==
             {header(sent, "cache-control"), header(sent, "etag") != nil}

    missing = Respond.json(authed(), 404, {:object, [{"error", "Record not found"}]})

    assert {"no-cache", nil, "Accept"} ==
             {header(missing, "cache-control"), header(missing, "etag"), header(missing, "vary")}
  end

  test "Accounts.settings/1 returns the raw settings JSON", %{id: id} do
    assert %{"maps" => %{"distance_unit" => "mi"}, "timezone" => "UTC"} = Accounts.settings(id)
  end
end
