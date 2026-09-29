defmodule DawarichWeb.Api.AuthTest do
  use Dawarich.IngestCase, async: false
  import Plug.Test
  import Plug.Conn

  alias Dawarich.{RailsCookies, RailsSecret}
  alias DawarichWeb.Api.{Auth, Respond}

  @base ~w(cache-control content-type referrer-policy x-content-type-options x-dawarich-response x-dawarich-version x-frame-options x-permitted-cross-domain-policies x-request-id x-runtime x-xss-protection)

  defp admission(params, headers \\ []) do
    conn(:post, "/api/v1/points")
    |> Map.update!(:req_headers, &(&1 ++ headers))
    |> assign(:api_params, params)
    |> fetch_cookies()
    |> Auth.admission()
  end

  defp names(conn), do: conn.resp_headers |> Enum.map(&elem(&1, 0)) |> Enum.sort()

  defp run(params, headers \\ []) do
    conn(:post, "/api/v1/points")
    |> Map.update!(:req_headers, &(&1 ++ headers))
    |> assign(:api_params, params)
    |> put_private(:dawarich_raw_body, "")
    |> Auth.call([])
  end

  defp header(conn, name), do: conn |> get_resp_header(name) |> List.first()

  defp session_for(id, salt) do
    RailsCookies.encrypt(
      %{"warden.user.user.key" => [[id], salt]},
      "_dawarich_session",
      RailsSecret.fetch()
    )
  end

  test "no key: 401 head, content type from Accept, Rails' header set" do
    conn = run(%{})
    assert {401, "", "text/html"} = {conn.status, conn.resp_body, header(conn, "content-type")}
    assert header(conn, "x-dawarich-response") == "Hey, I'm alive!"
    assert header(conn, "cache-control") == "no-cache"
    assert header(conn, "x-request-id") =~ ~r/\A[0-9a-f-]{36}\z/
    assert header(conn, "x-runtime") =~ ~r/\A\d+\.\d{6}\z/
    assert header(conn, "x-frame-options") == "SAMEORIGIN"
    assert header(conn, "vary") == nil

    assert header(run(%{}, [{"accept", "application/json"}]), "content-type") ==
             "text/html"
  end

  test "a key param wins over Bearer even when blank; an integer key is a string" do
    id = user!(%{api_key: "phoenix-a3-auth-key"})
    assert run(%{}, [{"authorization", "Bearer phoenix-a3-auth-key"}]).assigns.api_user.id == id

    assert run(%{"api_key" => ""}, [{"authorization", "Bearer phoenix-a3-auth-key"}]).status ==
             401

    user!(%{api_key: "12"})
    assert run(%{"api_key" => 12}).assigns.api_user
  end

  test "blank stored API keys are never authenticated" do
    blank = user!(%{})
    user!(%{api_key: "  "})

    assert %{rows: [[""]]} =
             Dawarich.Repo.query!("SELECT api_key FROM users WHERE id = $1", [blank])

    for {params, headers} <- [
          {%{"api_key" => ""}, []},
          {%{"api_key" => "  "}, []},
          {%{}, [{"authorization", "Bearer "}]},
          {%{}, [{"authorization", "Bearer   "}]}
        ] do
      assert run(params, headers).status == 401
    end
  end

  test "402 for pending payment, 401 JSON for inactive and expired users" do
    user!(%{api_key: "p", status: 3})
    user!(%{api_key: "i", status: 0, active_until: ~N[2099-01-01 00:00:00]})
    user!(%{api_key: "e", status: 1, active_until: ~N[2001-01-01 00:00:00]})

    pending = run(%{"api_key" => "p"}, [{"accept", "application/json"}])
    assert pending.status == 402

    assert pending.resp_body ==
             ~s({"error":"payment_required","message":"Complete your subscription to continue.","resume_url":null})

    assert header(pending, "vary") == "Accept"
    assert header(pending, "x-dawarich-response") == "Hey, I'm alive and authenticated!"
    assert run(%{"api_key" => "i"}).resp_body == ~s({"error":"User account is not active"})
    assert run(%{"api_key" => "e"}).resp_body == ~s({"error":"User subscription is not active"})
  end

  test "a soft-deleted user's key is unknown: 401" do
    user!(%{api_key: "phoenix-a3-deleted", deleted_at: ~N[2026-01-01 00:00:00]})
    assert run(%{"api_key" => "phoenix-a3-deleted"}).status == 401
  end

  test "Bearer: any case, any whitespace run, one token, outer whitespace stripped as Puma does; repeated Authorization lines match nothing" do
    id = user!(%{api_key: "phoenix-a3-bearer"})

    for value <- [
          "Bearer phoenix-a3-bearer",
          "bearer phoenix-a3-bearer",
          "Bearer \t phoenix-a3-bearer",
          " Bearer phoenix-a3-bearer \t"
        ],
        do: assert(run(%{}, [{"authorization", value}]).assigns.api_user.id == id, value)

    for value <- [
          "Bearer",
          "Bearer phoenix-a3-bearer extra",
          "Token phoenix-a3-bearer",
          "Bearerphoenix-a3-bearer"
        ],
        do: assert(run(%{}, [{"authorization", value}]).status == 401, value)

    assert run(%{}, [
             {"authorization", "Bearer phoenix-a3-bearer"},
             {"authorization", "Bearer phoenix-a3-bearer"}
           ]).status == 401
  end

  test "a format parameter picks the format without Vary; one outside json/html/xml/text goes to Rails" do
    assert {:ok, :json, false, nil} = admission(%{"format" => "json"}, [{"accept", "text/html"}])
    assert {:ok, :xml, false, nil} = admission(%{"format" => "xml"})
    assert {:replay, "format parameter"} = admission(%{"format" => "csv"})

    conn = run(%{"format" => "json"})

    assert {401, "text/html", nil} =
             {conn.status, header(conn, "content-type"), header(conn, "vary")}
  end

  test "mobile client parameters and ambiguous request headers go to Rails" do
    assert {:replay, "client header writes the session"} = admission(%{"client" => "ios"})
    assert {:replay, "client header writes the session"} = admission(%{"client" => "android"})
    assert {:replay, "ambiguous headers"} = admission(%{}, [{"x_dawarich_client", "ios"}])

    assert {:replay, "ambiguous headers"} =
             admission(%{}, [{"cookie", "a=1"}, {"cookie", "b=2"}])
  end

  test "Accept: blank, browser-like and single known types are owned; unknown, malformed and multi-valued ones go to Rails" do
    assert {:ok, :html, false, nil} = admission(%{})
    assert {:ok, :html, false, nil} = admission(%{}, [{"accept", "text/html, */*"}])
    assert {:ok, :json, true, nil} = admission(%{}, [{"accept", "application/json"}])
    assert {:replay, "Accept type"} = admission(%{}, [{"accept", "image/png"}])
    assert {:replay, "Accept type"} = admission(%{}, [{"accept", "application/json;;q"}])

    assert {:replay, "multi-valued Accept"} =
             admission(%{}, [{"accept", "application/json, text/plain"}])

    assert {:replay, "multi-valued Accept"} =
             admission(%{}, [{"accept", "application/json"}, {"accept", "text/plain"}])

    assert {:replay, "X-Requested-With"} =
             admission(%{}, [{"x-requested-with", "XMLHttpRequest"}])
  end

  test "a readable session without a signed-in user passes through with no Set-Cookie; remember-me without a session user goes to Rails; an unreadable session is harmless, like no session" do
    session =
      RailsCookies.encrypt(
        %{"session_id" => "phoenix-a3"},
        "_dawarich_session",
        RailsSecret.fetch()
      )

    assert {:ok, :html, false, nil} = admission(%{}, [{"cookie", "_dawarich_session=#{session}"}])

    assert {401, []} =
             run(%{}, [{"cookie", "_dawarich_session=#{session}"}])
             |> then(&{&1.status, get_resp_header(&1, "set-cookie")})

    assert {:replay, "remember-me cookie"} = admission(%{}, [{"cookie", "remember_user_token=x"}])

    assert {:replay, "remember-me cookie"} =
             admission(%{}, [{"cookie", "_dawarich_session=#{session}; remember_user_token=x"}])

    assert {:ok, :html, false, nil} =
             admission(%{}, [{"cookie", "_dawarich_session=garbage"}])

    assert {:replay, "remember-me cookie"} =
             admission(%{}, [{"cookie", "_dawarich_session=garbage; remember_user_token=x"}])
  end

  test "a valid signed-in session passes while deleted users and mismatched salts go to Rails" do
    password = "$2a$12$" <> String.duplicate("a", 53)
    id = user!(%{encrypted_password: password})
    session = session_for(id, String.slice(password, 0, 29))

    assert {:ok, :html, false, nil} =
             admission(%{}, [{"cookie", "_dawarich_session=#{session}; remember_user_token=x"}])

    Dawarich.Repo.query!("UPDATE users SET deleted_at = now() WHERE id = $1", [id])

    assert {:replay, "stale session"} =
             admission(%{}, [{"cookie", "_dawarich_session=#{session}"}])

    other = user!(%{encrypted_password: password})
    stale = session_for(other, "$2a$12$" <> String.duplicate("b", 22))
    assert {:replay, "stale session"} = admission(%{}, [{"cookie", "_dawarich_session=#{stale}"}])
  end

  test "a session lookup database error goes to Rails" do
    password = "$2a$12$" <> String.duplicate("a", 53)
    id = user!(%{encrypted_password: password})
    session = session_for(id, String.slice(password, 0, 29))

    Dawarich.Repo.query!("ALTER TABLE users RENAME TO session_lookup_users")

    assert {:replay, "session lookup failed: Postgrex.Error"} =
             admission(%{}, [{"cookie", "_dawarich_session=#{session}"}])
  end

  test "request IDs use the Puma-joined header value" do
    assert header(run(%{}, [{"x-request-id", "first"}]), "x-request-id") == "first"

    assert header(
             run(%{}, [{"x-request-id", "first"}, {"x-request-id", "second"}]),
             "x-request-id"
           ) ==
             "firstsecond"
  end

  test "every response Phoenix owns carries Rails' header set, and only it" do
    user!(%{api_key: "phoenix-a3-respond"})
    user!(%{api_key: "p", status: 3})
    user!(%{api_key: "i", status: 0, active_until: ~N[2099-01-01 00:00:00]})
    user!(%{api_key: "e", status: 1, active_until: ~N[2001-01-01 00:00:00]})
    admitted = run(%{"api_key" => "phoenix-a3-respond"}, [{"accept", "application/json"}])

    for {status, extra} <- [
          {200, ~w(etag vary)},
          {201, ~w(etag vary)},
          {422, ~w(vary)},
          {500, ~w(vary)}
        ] do
      sent = Respond.json(admitted, status, {:object, [{"k", "v"}]})
      assert names(sent) == Enum.sort(@base ++ extra), "#{status}"
      assert header(sent, "content-type") == "application/json; charset=utf-8"

      assert header(sent, "cache-control") ==
               if(status in [200, 201],
                 do: "max-age=0, private, must-revalidate",
                 else: "no-cache"
               )
    end

    assert names(run(%{})) == Enum.sort(@base)

    for key <- ~w(p i e),
        do:
          assert(
            names(run(%{"api_key" => key}, [{"accept", "application/json"}])) ==
              Enum.sort(@base ++ ["vary"]),
            key
          )
  end
end
