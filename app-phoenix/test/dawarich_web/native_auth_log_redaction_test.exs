defmodule DawarichWeb.NativeAuthLogRedactionTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  require Logger

  test "auth failure reports never expose OTP attempts backup codes or capabilities" do
    values = %{
      "otp_attempt" => "synthetic-otp-failure-value",
      "otp_backup_codes" => "synthetic-backup-failure-value",
      "password" => "synthetic-password-failure-value",
      "reset_password_token" => "synthetic-reset-failure-value",
      "link_token" => "synthetic-link-failure-value",
      "otp_secret" => "synthetic-secret-failure-value"
    }

    log =
      capture_log(fn ->
        try do
          raise "synthetic auth rendering failure"
        rescue
          error ->
            Logger.error(%{auth_failure: Exception.message(error), params: values})
            Logger.error("auth failure " <> URI.encode_query(values))
            Logger.flush()
        end
      end)

    safe? = Enum.all?(Map.values(values), &(not String.contains?(log, &1)))
    assert safe?
    assert log =~ "synthetic auth rendering failure"
    assert log =~ "[FILTERED]"
  end
end
