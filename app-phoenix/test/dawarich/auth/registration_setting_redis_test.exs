defmodule Dawarich.Auth.RegistrationSettingRedisTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  alias Dawarich.Auth.RegistrationSetting

  test "request read needs no live Redis" do
    start_supervised!({Redix, {"redis://127.0.0.1:1", [name: Dawarich.Redis.Cache]}})
    Dawarich.State.put_registration_enabled(ScratchRepo, false)

    assert RegistrationSetting.fetch(
             %{"ALLOW_EMAIL_PASSWORD_REGISTRATION" => "true"},
             ScratchRepo
           ) == {:ok, false}
  end
end
