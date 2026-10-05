defmodule DawarichWeb.AdminSettingWritesTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf
  alias DawarichWeb.AdminWrites.Settings

  defmodule RegistrationFailureRepo do
    def query!(sql, params, opts), do: Dawarich.Repo.query!(sql, params, opts)

    def transaction(_) do
      send(self(), :registration_sql_attempt)
      raise DBConnection.ConnectionError, message: "synthetic registration SQL refusal"
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.query!("DELETE FROM instance_settings", [], log: false)

    RailsUser.insert!(%{
      id: 15511,
      email: "a10b-instance-http@example.invalid",
      admin: true,
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    %{
      session: RailsUser.session(15511),
      context: %{self_hosted: true, oidc: false, env: %{}, command: fn _ -> {:ok, 0} end}
    }
  end

  test "instance HTTP save preserves section flash and terminal partial effects", c do
    assert Code.ensure_loaded?(Dawarich.Admin.InstanceWrites), "instance writes must exist"

    for {section, value, pinned, kind, message} <- [
          {"points", "false", %{}, "notice", "Settings saved."},
          {"unknown", "true", %{"STORE_GEODATA" => "true"}, "alert",
           "Refused: pinned by STORE_GEODATA."}
        ] do
      conn =
        request(c.session, [{"section", section}, {"instance_settings[store_geodata]", value}])
        |> Settings.call(action: :instance, context: %{c.context | env: pinned})

      assert conn.status == 303 and conn.halted and conn.resp_body == ""
      suffix = if section == "points", do: "?section=points", else: ""

      assert get_resp_header(conn, "location") == [
               "http://www.example.com/admin/settings" <> suffix
             ]

      assert conn.private.dawarich_rails_session_changes["flash"]["flashes"][kind] == message
    end

    conn =
      request(c.session, [
        {"section", "photon"},
        {"instance_settings[photon_api_host]", "bad host"}
      ])
      |> Settings.call(action: :instance, context: c.context)

    assert conn.status == 303

    assert get_resp_header(conn, "location") == [
             "http://www.example.com/admin/settings?section=photon"
           ]

    assert conn.private.dawarich_rails_session_changes["flash"]["flashes"]["alert"] =~
             "bare hostname"

    opts = [
      action: :instance,
      context: Map.put(c.context, :repo, Dawarich.Admin.InstanceWritesTest.LaterFailureRepo)
    ]

    conn =
      request(c.session, [
        {"instance_settings[store_geodata]", "true"},
        {"instance_settings[reverse_geocoding_rps]", "2.5"}
      ])
      |> Settings.call(opts)

    assert conn.status == 500 and conn.halted and conn.resp_body == ""

    assert Repo.query!("SELECT value FROM instance_settings WHERE key='store_geodata'", [],
             log: false
           ).rows == [[true]]

    refute Map.has_key?(conn.private, :dawarich_proxy_owner)
  end

  test "denied admin update and failed PG write preserve state and source HTTP outcome", c do
    alias Dawarich.Admin.SettingWrites
    Dawarich.State.put_registration_enabled(Repo, true)
    RailsUser.insert!(%{id: 15512, email: "a13g-denied-member@example.invalid"})
    member = Dawarich.Accounts.get(15512)
    admin = Dawarich.Accounts.get(15511)

    assert {:handoff, :actor} =
             SettingWrites.registration(member, %{"registration_enabled" => "0"}, c.context)

    assert {:handoff, :cloud} =
             SettingWrites.registration(admin, %{}, %{c.context | self_hosted: false})

    assert {:handoff, :oidc} = SettingWrites.registration(admin, %{}, %{c.context | oidc: true})

    assert Repo.query!("SELECT enabled FROM phoenix.registration_setting", [], log: false).rows ==
             [[true]]

    server = Dawarich.Test.RawHTTP.listen()
    parent = self()
    previous = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, server.port})

    on_exit(fn ->
      :gen_tcp.close(server.listen)
      Application.put_env(:dawarich, :rails_upstream, previous)
    end)

    start_supervised!(
      {Task,
       fn ->
         socket = Dawarich.Test.RawHTTP.accept(server)
         Dawarich.Test.RawHTTP.read_head(socket)
         send(parent, :registration_upstream_called)
         Dawarich.Test.RawHTTP.reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
         :gen_tcp.close(socket)
       end}
    )

    conn =
      request(
        c.session,
        [{"registration_enabled", "0"}],
        "/settings/users/update_registration_settings"
      )
      |> Settings.call(
        action: :registration,
        context: Map.put(c.context, :repo, RegistrationFailureRepo)
      )

    assert conn.status == 500 and conn.halted and conn.resp_body == ""
    assert_received :registration_sql_attempt
    refute_received :registration_upstream_called
    refute Map.has_key?(conn.private, :dawarich_proxy_owner)

    assert Repo.query!("SELECT enabled FROM phoenix.registration_setting", [], log: false).rows ==
             [[true]]
  end

  defp request(session, values, path \\ "/admin/settings") do
    raw =
      URI.encode_query([
        {"authenticity_token", RailsCsrf.masked_token(session)},
        {"_method", "patch"} | values
      ])

    Plug.Test.conn("POST", path, raw)
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("accept", "text/html")
  end
end
