defmodule DawarichWeb.NativeM4SessionsTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    RailsUser.insert!(%{
      id: 10841,
      email: "m4-session@example.invalid",
      api_key: "synthetic-m4-api",
      settings: %{
        "locale" => "en",
        "timezone" => "UTC",
        "immich_api_key" => "synthetic-m4-provider"
      }
    })

    :ok
  end

  defp live_as(path), do: live(RailsUser.signed_in(10841) |> RailsUser.connecting_as(10841), path)

  test "native job pages refuse a revoked session before params events and updates" do
    original = Accounts.get(10841).encrypted_password

    for action <- [:params, :event, :info] do
      Repo.query!("UPDATE users SET encrypted_password=$1 WHERE id=10841", [original], log: false)
      {:ok, view, _} = live_as("/exports")

      Repo.query!(
        "UPDATE users SET encrypted_password=$1 WHERE id=10841",
        ["changed-session-salt"],
        log: false
      )

      case action do
        :params -> render_patch(view, "/exports?page=2")
        :event -> render_hook(view, "changelog_consent", %{"decision" => "declined"})
        :info -> send(view.pid, :navbar_refresh)
      end

      assert_redirect(view, "/users/sign_in")
    end
  end

  test "native job principals omit credentials while preserving current URL and locale" do
    {:ok, view, html} = live_as("/notifications?locale=de&page=2")
    assert html =~ "/native/app"
    socket = :sys.get_state(view.pid).socket
    assert safe_principal?(socket.assigns.current_user)
    assert safe_principal?(socket.assigns.current_scope.user)
    assert socket.assigns.request_path == "/notifications"
    assert socket.assigns.query_params["page"] == "2"
    assert socket.assigns.locale == "de"
  end

  defp safe_principal?(user) do
    Map.get(user, :api_key) == nil and Map.get(user, :encrypted_password) == nil and
      Map.get(user.settings, "immich_api_key") == nil
  end

  test "onboarding QR reveal requires a fresh session and CSRF without socket credentials" do
    session = RailsUser.session(10841)

    conn =
      RailsUser.signed_in(10841, session)
      |> Plug.Conn.put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session))

    response = get(conn, "/native/account/qr")
    assert response.status == 200
    assert response.resp_body =~ "<svg"
    assert Plug.Conn.get_resp_header(response, "cache-control") == ["no-store"]
    assert get(RailsUser.signed_in(10841), "/native/account/qr").status == 403

    Repo.query!("UPDATE users SET encrypted_password=$1 WHERE id=10841", ["changed-session-salt"],
      log: false
    )

    assert get(conn, "/native/account/qr").status != 200
  end

  test "upload and phrase crash payloads and lazy iodata retain no capabilities" do
    require Logger

    values = %{
      "magic_phrase" => "synthetic-m4-phrase",
      "signed_id" => "synthetic-m4-signed",
      "url" => "synthetic-m4-target",
      "authorization" => "synthetic-m4-header",
      "checksum" => "synthetic-m4-checksum"
    }

    log =
      capture_log(fn ->
        {:ok, pid} = GenServer.start(Dawarich.Test.M4Crash, %{})
        monitor = Process.monitor(pid)

        send(pid, %Phoenix.Socket.Message{
          topic: "lv:m4",
          event: "event",
          payload: %{"value" => values}
        })

        assert_receive {:DOWN, ^monitor, :process, ^pid, _}
        Logger.error(fn -> ["m4 payload ", JSON.encode_to_iodata!(values)] end)
        Logger.flush()
      end)

    assert log =~ "m4 handler failed"
    assert log =~ "m4 payload"
    assert Enum.all?(Map.values(values), &(not String.contains?(log, &1)))
  end
end
