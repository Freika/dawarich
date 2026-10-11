defmodule DawarichWeb.NativeAuthFailureReportingTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  import ExUnit.CaptureLog
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{AuthAccountLink.Actions, RailsCsrf}

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    Dawarich.Test.NativeAuthHTTP.isolate_counters()
    old = System.get_env("FORCE_SSL")
    System.put_env("FORCE_SSL", "false")

    on_exit(fn ->
      if old, do: System.put_env("FORCE_SSL", old), else: System.delete_env("FORCE_SSL")
    end)

    :ok
  end

  test "real account-link domain failure reports only its exception type without auth values" do
    values =
      ~w(synthetic-otp-report synthetic-backup-report synthetic-password-report synthetic-reset-report synthetic-link-report synthetic-secret-report)

    session = %{
      "_csrf_token" => RailsCsrf.new_token(),
      "pending_oauth_link" => %{
        "user_id" => 7,
        "expires_at" => 1,
        "provider" => "github",
        "uid" => "synthetic"
      }
    }

    conn =
      Phoenix.ConnTest.build_conn(:get, "/auth/account_link/challenge")
      |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))

    context = %{clock: fn -> raise Enum.join(values, " ") end}

    log =
      capture_log(fn ->
        response = Actions.call(conn, enabled: true, native: true, context: context)
        assert response.status == 503
        assert response.halted
        Logger.flush()
      end)

    report_emitted = String.contains?(log, "Account-link authentication failed: RuntimeError")
    assert report_emitted
    safe = Enum.all?(values, &(not String.contains?(log, &1)))
    assert safe
  end
end
