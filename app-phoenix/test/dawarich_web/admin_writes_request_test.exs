defmodule DawarichWeb.AdminWritesRequestTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Auth.{ActionCsrf, Admission}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{AdminWritesGate, RailsCsrf}
  alias DawarichWeb.AdminWrites.{Request, Response}

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

  test "accepts only canonical forms with method path csrf and current admin", c do
    assert Code.ensure_loaded?(Request), "admin writes request module must exist"
    assert Code.ensure_loaded?(AdminWritesGate), "admin writes gate must exist"
    assert Code.ensure_loaded?(Response), "admin writes response module must exist"
    before = snapshot()

    for {action, path, methods} <- [
          {:create, "/settings/users", [{"POST", nil}]},
          {:update, "/settings/users/14002",
           [{"PATCH", nil}, {"PUT", nil}, {"POST", "patch"}, {"POST", "put"}]},
          {:registration, "/settings/users/update_registration_settings",
           [{"PATCH", nil}, {"POST", "patch"}]},
          {:instance, "/admin/settings",
           [{"PATCH", nil}, {"PUT", nil}, {"POST", "patch"}, {"POST", "put"}]},
          {:rotate, "/settings/users/14002/regenerate_api_key", [{"POST", nil}]},
          {:reset, "/settings/users/14002/send_password_reset", [{"POST", nil}]}
        ],
        {method, override} <- methods,
        kind <- [:global, :per_form] do
      effective = if override, do: String.upcase(override), else: method
      pairs = [{"authenticity_token", csrf(c.session, effective, path, kind)}]
      pairs = if override, do: pairs ++ [{"_method", override}], else: pairs
      pairs = if action in [:create, :update], do: pairs ++ [{"user[email]", ""}], else: pairs
      raw = URI.encode_query(pairs)
      conn = request(c.session, method, path, raw)
      assert AdminWritesGate.eligible?(conn, action, c.opts)
      {:ok, admitted, actor, params, context} = admit!(conn, action, c.opts)
      assert actor.id == 14001 and actor.admin
      assert context.method == effective
      refute Map.has_key?(params, "_method")
      same_body = admitted.private.dawarich_raw_body == raw
      assert same_body, "admitted body bytes changed"

      redirected =
        Response.redirect(admitted, 303, "/settings/users", :alert, "Synthetic validation")

      assert redirected.status == 303 and redirected.resp_body == "" and redirected.halted
      assert get_resp_header(redirected, "location") == ["http://www.example.com/settings/users"]

      assert redirected.private.dawarich_rails_session_changes["flash"]["flashes"]["alert"] ==
               "Synthetic validation"
    end

    for {method, raw} <- [
          {"DELETE", ""},
          {"POST", "_method=delete"},
          {"POST", "_method=PATCH"},
          {"PATCH", "_method=patch"},
          {"POST", "_method=post"}
        ] do
      handoff!(request(c.session, method, "/settings/users/14002", raw), :update, c.opts, raw)
    end

    for token <- [
          nil,
          "invalid",
          csrf(c.session, "PUT", "/settings/users/14002", :per_form),
          csrf(c.session, "PATCH", "/settings/users/14001", :per_form)
        ] do
      raw = if token, do: URI.encode_query(%{"authenticity_token" => token}), else: ""
      handoff!(request(c.session, "PATCH", "/settings/users/14002", raw), :update, c.opts, raw)
    end

    raw =
      URI.encode_query(%{
        "authenticity_token" => csrf(c.session, "POST", "/settings/users", :global)
      })

    handoff!(
      request(c.session, "POST", "/settings/users", raw)
      |> put_req_header("origin", "http://other.invalid"),
      :create,
      c.opts,
      raw
    )

    for session <- [
          %{},
          RailsUser.session(14002),
          Map.put(c.session, "invitation_token", "synthetic"),
          Map.put(c.session, "warden.user.user.key", [[14001], "changed-salt"])
        ] do
      handoff!(request(session, "POST", "/settings/users", raw), :create, c.opts, raw)
    end

    handoff!(
      request(c.session, "POST", "/settings/users", raw),
      :create,
      [context: %{self_hosted: false, oidc: false}],
      raw
    )

    conn = request(c.session, "POST", "/settings/users", raw)
    assert AdminWritesGate.eligible?(conn, :create, c.opts)
    Repo.query!("UPDATE users SET admin=false WHERE id=14001", [], log: false)
    demoted = snapshot()

    handoff!(
      assign(conn, :current_user, %{Accounts.get(14001) | admin: true}),
      :create,
      c.opts,
      raw
    )

    assert snapshot() == demoted
    Repo.query!("UPDATE users SET admin=true WHERE id=14001", [], log: false)
    assert snapshot() == before
  end

  test "preserves raw fallback and permits only source hidden checkbox pairs", c do
    assert Code.ensure_loaded?(Request), "admin writes request module must exist"
    before = snapshot()

    for {action, path, name, unchecked, checked} <- [
          {:update, "/settings/users/14002", "user[admin]", "0", "1"},
          {:registration, "/settings/users/update_registration_settings", "registration_enabled",
           "0", "1"},
          {:instance, "/admin/settings", "instance_settings[photon_api_use_https]", "false",
           "true"},
          {:instance, "/admin/settings", "instance_settings[nominatim_api_use_https]", "false",
           "true"},
          {:instance, "/admin/settings", "instance_settings[store_geodata]", "false", "true"}
        ],
        values <- [[unchecked], [unchecked, checked]] do
      pairs =
        [{"authenticity_token", csrf(c.session, "PATCH", path, :per_form)}] ++
          Enum.map(values, &{name, &1})

      raw = URI.encode_query(pairs)
      {:ok, _, _, params, _} = admit!(request(c.session, "PATCH", path, raw), action, c.opts)
      assert params[name] == List.last(values)
    end

    for raw <- [
          "user%5Bemail%5D=a&user%5Bemail%5D=b",
          "user%5Badmin%5D=1&user%5Badmin%5D=0",
          "user%5Badmin%5D=0&user%5Badmin%5D=1&user%5Badmin%5D=1",
          "commit=a&commit=a",
          "user%5Badmin%5D=0&user%5Badmin%5D=0",
          "user%5Bemail%5D=%FF",
          "user%5Bemail%5D=%ZZ",
          "user%5Bemail%5D%5Bnested%5D=x",
          "unexpected=x"
        ] do
      raw =
        raw <>
          "&" <>
          URI.encode_query(%{
            "authenticity_token" => csrf(c.session, "PATCH", "/settings/users/14002", :global)
          })

      handoff!(request(c.session, "PATCH", "/settings/users/14002", raw), :update, c.opts, raw)
    end

    for fixture <-
          ~w(checked_https unchecked_https checked_store unchecked_store registration_checked registration_unchecked) do
      row = fixture("admin_setting_writes", fixture)
      action = if String.starts_with?(fixture, "registration"), do: :registration, else: :instance

      path =
        if action == :registration,
          do: "/settings/users/update_registration_settings",
          else: "/admin/settings"

      raw =
        String.replace(
          row["body"],
          "authenticity_token=CSRF",
          URI.encode_query(%{"authenticity_token" => csrf(c.session, "PATCH", path, :per_form)})
        )

      admit!(request(c.session, "POST", path, raw), action, c.opts)
    end

    raw = "user%5Bemail%5D=a&authenticity_token=invalid"
    base = request(c.session, "PATCH", "/settings/users/14002", raw)

    for conn <- [
          put_req_header(base, "content-type", "application/json"),
          put_req_header(base, "content-type", "multipart/form-data;boundary=a"),
          put_req_header(base, "transfer-encoding", "chunked"),
          put_req_header(base, "accept", "application/json"),
          put_req_header(base, "turbo-frame", "frame"),
          %{base | req_headers: [{"content-type", "application/json"} | base.req_headers]},
          request(c.session, "PATCH", "/settings/users/14002?format=html", raw)
        ] do
      handoff!(conn, :update, c.opts, raw)
    end

    assert Admission.form("user%5Badmin%5D=0&user%5Badmin%5D=1", "", ["user[admin]"]) ==
             {:handoff, :duplicate_parameters}

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
  test "proxied admin writes preserve CSRF origin session and role admission", c do
    Dawarich.State.put_registration_enabled(Repo, false)

    for {action, method, path, fields} <- proxy_actions() do
      effective = if action == :registration, do: "PATCH", else: method

      raw =
        URI.encode_query([
          {"authenticity_token", csrf(c.session, effective, path, :per_form)} | fields
        ])

      conn = request(c.session, method, path, raw)
      conn = %{conn | remote_ip: {127, 0, 0, 1}}
      conn = put_req_header(conn, "x-forwarded-for", "192.0.2.5, 10.0.0.2")
      admitted = match?({:ok, _, %{id: 14001}, _, _}, Request.load(conn, action, c.opts))
      assert admitted, "proxied #{action} should be admitted"

      if action == :registration do
        response =
          DawarichWeb.AdminWrites.Settings.call(conn,
            action: :registration,
            context: c.opts[:context]
          )

        assert response.status == 302

        assert Repo.query!("SELECT enabled FROM phoenix.registration_setting", [], log: false).rows ==
                 [[true]]
      end

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

      if action != :background do
        nonadmin_session = RailsUser.session(14002)
        nonadmin_raw = role_body(nonadmin_session, effective, path, fields)
        nonadmin = request(nonadmin_session, method, path, nonadmin_raw)

        assert {:handoff, _} =
                 Request.load(
                   put_req_header(nonadmin, "x-forwarded-for", "192.0.2.5"),
                   action,
                   c.opts
                 )
      end
    end
  end

  @tag :review_conflict
  test "untrusted conflicting Client-IP and XFF refuse a valid admin registration envelope", c do
    path = "/settings/users/update_registration_settings"

    raw =
      URI.encode_query([
        {"authenticity_token", csrf(c.session, "PATCH", path, :per_form)},
        {"_method", "patch"},
        {"registration_enabled", "1"}
      ])

    conn = request(c.session, "POST", path, raw)
    conn = %{conn | remote_ip: {198, 51, 100, 20}}
    conn = put_req_header(conn, "x-forwarded-for", "192.0.2.5")
    assert match?({:ok, _, _, _, _}, Request.load(conn, :registration, c.opts))
    assert DawarichWeb.RailsRemoteIp.ip(conn) == "198.51.100.20"
    conflict = put_req_header(conn, "client-ip", "198.51.100.4")
    assert Admission.context(c.session, conflict, false, true) == {:handoff, :client_ip}

    assert_raise DawarichWeb.RailsRemoteIp.IpSpoofAttackError, fn ->
      DawarichWeb.RailsRemoteIp.ip(conflict)
    end

    assert match?({:handoff, _}, Request.load(conflict, :registration, c.opts))
  end

  @tag :review_role
  test "proxied nonadmin writes with valid session CSRF are refused solely by role", c do
    session = RailsUser.session(14002)

    for {action, method, path, fields} <- proxy_actions(), action != :background do
      effective = if action == :registration, do: "PATCH", else: method
      raw = role_body(session, effective, path, fields)
      token = URI.decode_query(raw)["authenticity_token"]

      assert ActionCsrf.valid?(session, token, effective, path),
             "#{action} needs valid nonadmin CSRF"

      conn = request(session, method, path, raw)
      conn = %{conn | remote_ip: {127, 0, 0, 1}}
      conn = put_req_header(conn, "x-forwarded-for", "192.0.2.5")
      refute AdminWritesGate.eligible?(conn, action, c.opts), "#{action} must enforce role"
      assert match?({:handoff, _}, Request.load(conn, action, c.opts))
      Repo.query!("UPDATE users SET admin=true WHERE id=14002", [], log: false)
      assert AdminWritesGate.eligible?(conn, action, c.opts)
      assert match?({:ok, _, %{id: 14002}, _, _}, Request.load(conn, action, c.opts))
      Repo.query!("UPDATE users SET admin=false WHERE id=14002", [], log: false)
    end
  end

  defp role_body(session, method, path, fields) do
    URI.encode_query([{"authenticity_token", csrf(session, method, path, :per_form)} | fields])
  end

  defp proxy_actions do
    [
      {:create, "POST", "/settings/users", [{"user[email]", ""}]},
      {:update, "PATCH", "/settings/users/14002", [{"user[email]", ""}]},
      {:registration, "POST", "/settings/users/update_registration_settings",
       [{"_method", "patch"}, {"registration_enabled", "1"}]},
      {:instance, "PATCH", "/admin/settings", []},
      {:background, "PATCH", "/settings/background_jobs",
       [{"settings[visits_suggestions_enabled]", "true"}]},
      {:rotate, "POST", "/settings/users/14002/regenerate_api_key", []},
      {:reset, "POST", "/settings/users/14002/send_password_reset", []},
      {:destroy, "DELETE", "/settings/users/14002", []},
      {:test_geocoding, "POST", "/admin/settings/test_geocoding", []},
      {:test_map_matching, "POST", "/admin/settings/test_map_matching", []}
    ]
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
