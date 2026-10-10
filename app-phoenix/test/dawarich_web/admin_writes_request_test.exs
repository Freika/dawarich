defmodule DawarichWeb.AdminWritesRequestTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Auth.Admission
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{AdminWritesGate, RailsCsrf}
  alias DawarichWeb.AdminWrites.{Request, Response}

  @path "/settings/background_jobs"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: 14001,
      email: "a10b-admin@example.invalid",
      admin: true,
      settings: %{"locale" => "en", "timezone" => "UTC", "onboarding_completed" => true}
    })

    RailsUser.insert!(%{
      id: 14002,
      email: "a10b-target@example.invalid",
      admin: false,
      settings: %{"locale" => "en", "timezone" => "UTC", "onboarding_completed" => true}
    })

    %{session: RailsUser.session(14001), opts: [context: %{self_hosted: true, oidc: false}]}
  end

  test "accepts only canonical background forms with method path csrf and current session", c do
    assert Code.ensure_loaded?(Response), "admin writes response module must exist"
    before = snapshot()

    for {fields, methods} <- [
          {[{"job_name", "start_reverse_geocoding"}], [{"POST", nil}]},
          {[{"settings[visits_suggestions_enabled]", "true"}],
           [{"PATCH", nil}, {"POST", "patch"}]}
        ],
        {method, override} <- methods,
        kind <- [:global, :per_form] do
      effective = if override, do: String.upcase(override), else: method
      pairs = [{"authenticity_token", csrf(c.session, effective, @path, kind)}]
      pairs = if override, do: pairs ++ [{"_method", override}], else: pairs
      raw = URI.encode_query(pairs ++ fields)
      conn = request(c.session, method, @path, raw)
      assert AdminWritesGate.eligible?(conn, :background, c.opts)
      {:ok, admitted, actor, params, context} = admit!(conn, :background, c.opts)
      assert actor.id == 14001
      assert context.method == effective
      refute Map.has_key?(params, "_method")
      same_body = admitted.private.dawarich_raw_body == raw
      assert same_body, "admitted body bytes changed"

      redirected =
        Response.redirect(admitted, 303, @path, :alert, "Synthetic validation")

      assert redirected.status == 303 and redirected.resp_body == "" and redirected.halted

      assert get_resp_header(redirected, "location") == [
               "http://www.example.com/settings/background_jobs"
             ]

      assert redirected.private.dawarich_rails_session_changes["flash"]["flashes"]["alert"] ==
               "Synthetic validation"
    end

    toggle = "settings%5Bvisits_suggestions_enabled%5D=true"

    for {method, raw} <- [
          {"PUT", toggle},
          {"DELETE", toggle},
          {"POST", "_method=delete&" <> toggle},
          {"POST", "_method=put&" <> toggle},
          {"PATCH", "_method=patch&" <> toggle},
          {"POST", "_method=patch&job_name=start_reverse_geocoding"}
        ] do
      handoff!(request(c.session, method, @path, raw), :background, c.opts, raw)
    end

    for token <- [
          nil,
          "invalid",
          csrf(c.session, "PUT", @path, :per_form),
          csrf(c.session, "PATCH", "/settings/users", :per_form)
        ] do
      raw =
        if token,
          do: toggle <> "&" <> URI.encode_query(%{"authenticity_token" => token}),
          else: toggle

      handoff!(request(c.session, "PATCH", @path, raw), :background, c.opts, raw)
    end

    raw =
      toggle <>
        "&" <>
        URI.encode_query(%{"authenticity_token" => csrf(c.session, "PATCH", @path, :global)})

    handoff!(
      request(c.session, "PATCH", @path, raw) |> put_req_header("origin", "http://other.invalid"),
      :background,
      c.opts,
      raw
    )

    for session <- [
          %{},
          Map.put(c.session, "invitation_token", "synthetic"),
          Map.put(c.session, "warden.user.user.key", [[14001], "changed-salt"])
        ] do
      handoff!(request(session, "PATCH", @path, raw), :background, c.opts, raw)
    end

    handoff!(
      request(c.session, "PATCH", @path, raw),
      :background,
      [context: %{self_hosted: false, oidc: false}],
      raw
    )

    conn = request(c.session, "PATCH", @path, raw)
    assert AdminWritesGate.eligible?(conn, :background, c.opts)
    Repo.query!("UPDATE users SET deleted_at=now() WHERE id=14001", [], log: false)
    handoff!(assign(conn, :current_user, Accounts.get(14001)), :background, c.opts, raw)
    Repo.query!("UPDATE users SET deleted_at=NULL WHERE id=14001", [], log: false)
    assert snapshot() == before
  end

  test "preserves raw fallback and refuses malformed background forms", c do
    before = snapshot()
    token = URI.encode_query(%{"authenticity_token" => csrf(c.session, "PATCH", @path, :global)})

    for raw <- [
          "settings%5Bvisits_suggestions_enabled%5D=true&settings%5Bvisits_suggestions_enabled%5D=false",
          "commit=a&commit=a&settings%5Bvisits_suggestions_enabled%5D=true",
          "settings%5Bvisits_suggestions_enabled%5D=%FF",
          "settings%5Bvisits_suggestions_enabled%5D=%ZZ",
          "settings%5Bvisits_suggestions_enabled%5D%5Bnested%5D=x",
          "settings%5Bvisits_suggestions_enabled%5D=true&unexpected=x",
          "commit=Save"
        ] do
      raw = raw <> "&" <> token
      handoff!(request(c.session, "PATCH", @path, raw), :background, c.opts, raw)
    end

    raw = "settings%5Bvisits_suggestions_enabled%5D=true&authenticity_token=invalid"
    base = request(c.session, "PATCH", @path, raw)

    for conn <- [
          put_req_header(base, "content-type", "application/json"),
          put_req_header(base, "content-type", "multipart/form-data;boundary=a"),
          put_req_header(base, "transfer-encoding", "chunked"),
          put_req_header(base, "accept", "application/json"),
          put_req_header(base, "turbo-frame", "frame"),
          %{base | req_headers: [{"content-type", "application/json"} | base.req_headers]}
        ] do
      handoff!(conn, :background, c.opts, raw)
    end

    assert Admission.form(
             "settings%5Bvisits_suggestions_enabled%5D=true&settings%5Bvisits_suggestions_enabled%5D=false",
             "",
             ["settings[visits_suggestions_enabled]"]
           ) == {:handoff, :duplicate_parameters}

    assert snapshot() == before
  end

  test "admits the existing background Turbo query independently of its body", c do
    assert Code.ensure_loaded?(Request), "admin writes request module must exist"
    session = RailsUser.session(14002)
    before = snapshot()

    for fixture <-
          ~w(background_query_true background_query_false background_override background_body) do
      row = fixture("admin_setting_writes", fixture)
      query = row["query"] || ""
      method = if fixture == "background_override", do: "POST", else: "PATCH"
      raw = row["body"]

      conn =
        request(session, method, "/settings/background_jobs?" <> query, raw)
        |> put_req_header("accept", "text/vnd.turbo-stream.html, text/html")
        |> put_req_header(
          "x-csrf-token",
          csrf(session, "PATCH", "/settings/background_jobs", :global)
        )

      {:ok, returned, actor, params, _} = admit!(conn, :background, c.opts)
      refute actor.admin
      assert params["settings[visits_suggestions_enabled]"] in ["true", "false"]
      assert returned.query_string == query
    end

    for {query, body} <- [
          {"settings%5Bvisits_suggestions_enabled%5D=true&settings%5Bvisits_suggestions_enabled%5D=true",
           ""},
          {"settings%5Bvisits_suggestions_enabled%5D=true&extra=x", ""},
          {"settings%5Bvisits_suggestions_enabled%5D=true",
           "settings%5Bvisits_suggestions_enabled%5D=false"},
          {"settings%5Bvisits_suggestions_enabled%5D=true",
           "settings%5Bvisits_suggestions_enabled%5D=true"},
          {"settings%5Bvisits_suggestions_enabled%5D=1", ""},
          {"locale=en", ""}
        ] do
      conn =
        request(session, "PATCH", "/settings/background_jobs?" <> query, body)
        |> put_req_header(
          "x-csrf-token",
          csrf(session, "PATCH", "/settings/background_jobs", :global)
        )

      returned = handoff!(conn, :background, c.opts, body)
      assert returned.query_string == query
    end

    assert snapshot() == before
  end

  @tag :proxy_admission
  test "proxied background writes preserve CSRF origin and session admission", c do
    for {method, fields} <- [
          {"PATCH", [{"settings[visits_suggestions_enabled]", "true"}]},
          {"POST", [{"job_name", "start_reverse_geocoding"}]}
        ] do
      action = :background
      path = @path
      raw = role_body(c.session, method, path, fields)

      conn = request(c.session, method, path, raw)
      conn = %{conn | remote_ip: {127, 0, 0, 1}}
      conn = put_req_header(conn, "x-forwarded-for", "192.0.2.5, 10.0.0.2")
      admitted = match?({:ok, _, %{id: 14001}, _, _}, Request.load(conn, action, c.opts))
      assert admitted, "proxied #{action} should be admitted"

      assert DawarichWeb.RailsRemoteIp.ip(conn) == "192.0.2.5"

      for refused <- [
            put_req_header(conn, "origin", "http://foreign.invalid"),
            put_req_header(conn, "cookie", ""),
            %{conn | req_headers: [{"x-forwarded-for", "192.0.2.6"} | conn.req_headers]},
            put_req_header(conn, "client-ip", "198.51.100.4")
          ] do
        assert {:handoff, _} = Request.load(refused, action, c.opts)
      end

      invalid =
        request(
          c.session,
          method,
          path,
          URI.encode_query([{"authenticity_token", "invalid"} | fields])
        )

      invalid = put_req_header(invalid, "x-forwarded-for", "192.0.2.5")
      assert {:handoff, _} = Request.load(invalid, action, c.opts)
    end
  end

  @tag :review_conflict
  test "untrusted conflicting Client-IP and XFF refuse a valid background toggle envelope", c do
    raw =
      URI.encode_query([
        {"authenticity_token", csrf(c.session, "PATCH", @path, :per_form)},
        {"_method", "patch"},
        {"settings[visits_suggestions_enabled]", "true"}
      ])

    conn = request(c.session, "POST", @path, raw)
    conn = %{conn | remote_ip: {198, 51, 100, 20}}
    conn = put_req_header(conn, "x-forwarded-for", "192.0.2.5")
    assert match?({:ok, _, _, _, _}, Request.load(conn, :background, c.opts))
    assert DawarichWeb.RailsRemoteIp.ip(conn) == "198.51.100.20"
    conflict = put_req_header(conn, "client-ip", "198.51.100.4")
    assert Admission.context(c.session, conflict, false, true) == {:handoff, :client_ip}

    assert_raise DawarichWeb.RailsRemoteIp.IpSpoofAttackError, fn ->
      DawarichWeb.RailsRemoteIp.ip(conflict)
    end

    assert match?({:handoff, _}, Request.load(conflict, :background, c.opts))
  end

  defp role_body(session, method, path, fields) do
    URI.encode_query([{"authenticity_token", csrf(session, method, path, :per_form)} | fields])
  end

  defp fixture(dir, name), do: File.read!("test/fixtures/#{dir}/#{name}.json") |> Jason.decode!()

  defp snapshot,
    do:
      Repo.query!("SELECT id,email,admin,status,updated_at FROM users ORDER BY id", [],
        log: false
      ).rows

  defp admit!(conn, action, opts) do
    result = Request.load(conn, action, opts)
    admitted = match?({:ok, _, _, _, _}, result)
    assert admitted, "request should be admitted"
    result
  end

  defp handoff!(conn, action, opts, expected) do
    result = Request.load(conn, action, opts)
    handed = match?({:handoff, _}, result)
    assert handed, "request should hand back before effects"
    {:handoff, returned} = result

    raw =
      case returned.private[:dawarich_raw_body] do
        nil ->
          {:ok, bytes, _} = read_body(returned)
          bytes

        bytes ->
          bytes
      end

    same = raw == expected
    assert same, "fallback bytes changed"
    same_envelope = returned.method == conn.method and returned.req_headers == conn.req_headers
    assert same_envelope, "fallback headers or method changed"
    returned
  end

  defp request(session, method, path, raw) do
    Plug.Test.conn(method, path, raw)
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded;charset=UTF-8")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("origin", "http://www.example.com")
    |> put_req_header("accept", "text/html")
  end

  defp csrf(session, _method, _path, :global), do: RailsCsrf.masked_token(session)

  defp csrf(session, method, path, :per_form) do
    raw = Base.url_decode64!(session["_csrf_token"], padding: false)
    expected = :crypto.mac(:hmac, :sha256, raw, path <> "#" <> String.downcase(method))
    pad = :crypto.strong_rand_bytes(32)
    Base.url_encode64(pad <> :crypto.exor(pad, expected), padding: false)
  end
end
