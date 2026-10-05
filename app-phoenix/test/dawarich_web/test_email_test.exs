defmodule DawarichWeb.TestEmailTest do
  use ExUnit.Case, async: false
  import Plug.Conn

  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{RailsCsrf, TestEmail, TestEmailGate}

  @path "/settings/general/test_email"
  @id 460_110
  @clock %{local: ~N[2026-10-04 12:00:00], offset: 0, zone: "UTC", valid: true}
  @env %{
    "SMTP_SERVER" => "synthetic.test",
    "SMTP_AUTHENTICATION" => "none",
    "SMTP_STARTTLS" => "false",
    "SMTP_FROM" => "Dawarich <residual@dawarich.test>",
    "TIME_ZONE" => "UTC"
  }
  @fixture Path.expand("../fixtures/mail/residual/http.json", __DIR__)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: @id,
      email: "test-email@test",
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    %{
      session: RailsUser.session(@id),
      opts: [context: %{self_hosted: true, oidc: false, env: @env}, clock: @clock]
    }
  end

  test "test mail POST matches Rails HTML and Turbo responses with action CSRF", c do
    assert Code.ensure_loaded?(TestEmail), "test mail HTTP plug must exist"
    assert Code.ensure_loaded?(TestEmailGate), "test mail gate must exist"
    cases = @fixture |> File.read!() |> Jason.decode!() |> Map.fetch!("cases")
    assert length(cases) == 34

    admitted =
      ~w(html_success turbo_success not_configured preferred_de socket_error timeout_error ssl_error system_error argument_error smtp_error unsafe_error turbo_error mixed_accept smtp_fatal smtp_busy smtp_syntax smtp_auth_reply smtp_unknown smtp_multiline turbo_smtp_fatal)

    for row <- Enum.filter(cases, &(&1["id"] in admitted)) do
      Repo.query!(
        "UPDATE public.users SET email=$2,settings=$3 WHERE id=$1",
        [@id, row["recipient"], %{"locale" => row["preference"], "timezone" => "UTC"}],
        log: false
      )

      env = if row["configured"], do: @env, else: Map.delete(@env, "SMTP_SERVER")
      opts = Keyword.put(c.opts, :context, %{self_hosted: true, oidc: false, env: env})

      Process.put(:transport_result, Dawarich.Mail.TestTransport.result(row))
      before = snapshot()

      conn =
        request(c.session, "POST", @path, "", [{"accept", row["accept"]}]) |> TestEmail.call(opts)

      assert conn.status == row["response"]["status"], row["id"]
      assert get_resp_header(conn, "x-dawarich-mail-owner") == ["native-test-email"]
      assert get_resp_header(conn, "x-dawarich-admin-owner") == []

      if row["response"]["body"] do
        if conn.resp_body != row["response"]["body"],
          do: flunk("Turbo body differs: #{row["id"]}")
      else
        assert get_resp_header(conn, "location") == [row["response"]["location"]]

        assert conn.private.dawarich_rails_session_changes["flash"]["flashes"] ==
                 row["response"]["flash"]
      end

      refute_received {:mail, _}
      refute_received {:mail, _}
      [users, outbox, jobs] = snapshot()
      assert [users, outbox] == Enum.take(before, 2)
      assert length(jobs) == length(List.last(before)) + row["queued"]
      Process.delete(:transport_result)
    end

    base = request(c.session, "POST", @path, "")
    assert TestEmailGate.eligible?(base, c.opts)

    for {method, path, raw, headers} <- [
          {"GET", @path, "", []},
          {"HEAD", @path, "", []},
          {"POST", @path <> ".json", "", []},
          {"POST", @path <> "?locale=de", "", []},
          {"POST", @path, "_method=post", []},
          {"POST", @path, "user_id=460999", []},
          {"POST", @path, "commit=a&commit=b", []},
          {"POST", @path, "commit=%ZZ", []},
          {"POST", @path, "locale=de", []},
          {"POST", @path, "", [{"accept", "application/json"}]},
          {"POST", @path, "", [{"content-type", "application/json"}]},
          {"POST", @path, "", [{"content-type", "multipart/form-data; boundary=synthetic"}]},
          {"POST", @path, "", [{"x-http-method-override", "PATCH"}]},
          {"POST", @path, "", [{"origin", "http://other.test"}]},
          {"POST", @path, "", [{"turbo-frame", "frame"}]}
        ] do
      conn = request(c.session, method, path, raw, headers)
      before = snapshot()
      result = TestEmail.admit(conn, c.opts)
      assert(match?({:handoff, _}, result), "unsupported request admitted")
      {:handoff, replay} = result
      if replay.private[:dawarich_raw_body], do: assert(replay.private.dawarich_raw_body == raw)
      refute_received {:mail, _}
      [users, outbox, jobs] = snapshot()
      assert [users, outbox] == Enum.take(before, 2)
      assert length(jobs) == length(List.last(before)) + 0
    end

    for token <- [nil, "invalid", RailsCsrf.masked_form_token(c.session, "/other", "POST")] do
      conn = request(c.session, "POST", @path, "") |> delete_req_header("x-csrf-token")
      conn = if token, do: put_req_header(conn, "x-csrf-token", token), else: conn
      assert_handoff(TestEmail.admit(conn, c.opts))
      refute_received {:mail, _}
    end

    duplicate = %{base | req_headers: [{"accept", "text/html"} | base.req_headers]}
    assert_handoff(TestEmail.admit(duplicate, c.opts))
    assert_handoff(TestEmail.admit(base, context: %{self_hosted: false, oidc: false, env: @env}))
    assert_handoff(TestEmail.admit(request(%{}, "POST", @path, ""), c.opts))

    assert_handoff(
      TestEmail.admit(
        request(Map.put(c.session, "invitation_token", "synthetic"), "POST", @path, ""),
        c.opts
      )
    )

    assert_handoff(
      TestEmail.admit(base,
        context: %{
          self_hosted: true,
          oidc: false,
          env: Map.put(@env, "SMTP_AUTHENTICATION", "unsupported")
        }
      )
    )

    refute_received {:mail, _}

    for env <- [
          Map.put(@env, "SMTP_AUTHENTICATION", "plain"),
          Map.put(@env, "SMTP_STARTTLS", "true"),
          Map.put(@env, "SMTP_SSL", "true")
        ] do
      assert_handoff(TestEmail.admit(base, context: %{self_hosted: true, oidc: false, env: env}))
      refute_received {:mail, _}
    end
  end

  defp request(session, method, path, raw, headers \\ []) do
    conn =
      Plug.Test.conn(method, path, raw)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(raw)))
      |> put_req_header("accept", "text/html")
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))

    token = RailsCsrf.masked_form_token(session, URI.parse(path).path, method)
    conn = if token, do: put_req_header(conn, "x-csrf-token", token), else: conn
    Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)
  end

  defp assert_handoff(result),
    do: assert(match?({:handoff, _}, result), "unsupported request admitted")

  defp snapshot do
    for table <- ~w(public.users public.job_outbox oban.oban_jobs) do
      Repo.query!("SELECT to_jsonb(t) FROM #{table} t ORDER BY to_jsonb(t)::text", [], log: false).rows
    end
  end
end
