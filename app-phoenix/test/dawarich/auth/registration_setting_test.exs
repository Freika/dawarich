defmodule Dawarich.Auth.RegistrationSettingTest do
  use ExUnit.Case, async: true

  alias Dawarich.Auth.RegistrationSetting

  @activation Path.expand("../../fixtures/auth/activation.json", __DIR__)
  @external_resource @activation
  @fixture Jason.decode!(File.read!(@activation))

  defp redis(reply), do: fn ["GET", "dawarich/registration_enabled"] -> reply end
  defp bytes(name), do: Base.decode64!(@fixture["registration"][name])

  test "reads the flag Rails' cache store wrote" do
    assert RegistrationSetting.fetch(%{}, redis({:ok, bytes("true")})) == {:ok, true}
    assert RegistrationSetting.fetch(%{}, redis({:ok, bytes("false")})) == {:ok, false}
    assert RegistrationSetting.fetch(%{}, redis({:ok, bytes("nil")})) == {:ok, nil}
  end

  test "a missing entry answers ALLOW_EMAIL_PASSWORD_REGISTRATION as Rails' fetch block does" do
    missing = redis({:ok, nil})

    assert RegistrationSetting.fetch(%{"ALLOW_EMAIL_PASSWORD_REGISTRATION" => "true"}, missing) ==
             {:ok, true}

    assert RegistrationSetting.fetch(%{"ALLOW_EMAIL_PASSWORD_REGISTRATION" => "TRUE"}, missing) ==
             {:ok, false}

    assert RegistrationSetting.fetch(%{}, missing) == {:ok, false}
  end

  test "anything else is unknown" do
    expiring = <<0, 0x11, 1, 5.0e9::little-float-64, -1::little-signed-32, 4, 8, ?T>>
    versioned = <<0, 0x11, 1, -1.0::little-float-64, 1::little-signed-32, ?v, 4, 8, ?T>>
    string = <<0, 0x11, 2, -1.0::little-float-64, -1::little-signed-32, "true">>

    for reply <- [
          {:ok, expiring},
          {:ok, versioned},
          {:ok, string},
          {:ok, <<4, 8, ?T>>},
          {:error, {:exit, :noproc}}
        ],
        do: assert(RegistrationSetting.fetch(%{}, redis(reply)) == :error)
  end
end
