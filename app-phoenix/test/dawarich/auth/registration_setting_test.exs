defmodule Dawarich.Auth.RegistrationSettingTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Auth.RegistrationSetting
  alias Dawarich.State

  @activation Path.expand("../../fixtures/auth/activation.json", __DIR__)

  defmodule FailureRepo do
    def transaction(fun), do: {:ok, fun.()}
    def query!(_, _, _), do: raise(DBConnection.ConnectionError, message: "synthetic PG refusal")
  end

  test "native registration reads copied false and stored nil without Redis" do
    config = Application.fetch_env!(:dawarich, :redis)

    options =
      Dawarich.Redis.options(config[:url], config[:cache_database]) |> Keyword.delete(:name)

    conn = start_supervised!({Redix, {config[:url], options}})
    {:ok, prior} = Redix.command(conn, ["GET", "dawarich/registration_enabled"])
    fixture = @activation |> File.read!() |> Jason.decode!()
    bytes = Base.decode64!(fixture["registration"]["true"])

    try do
      assert {:ok, "OK"} = Redix.command(conn, ["SET", "dawarich/registration_enabled", bytes])

      for value <- [false, nil] do
        State.put_registration_enabled(ScratchRepo, value)

        assert {:ok, ^value} =
                 RegistrationSetting.fetch(
                   %{"ALLOW_EMAIL_PASSWORD_REGISTRATION" => "true"},
                   ScratchRepo
                 )

        assert {:ok, ^bytes} = Redix.command(conn, ["GET", "dawarich/registration_enabled"])
      end
    after
      if prior,
        do: Redix.command(conn, ["SET", "dawarich/registration_enabled", prior]),
        else: Redix.command(conn, ["DEL", "dawarich/registration_enabled"])
    end
  end

  test "native writes update initialized PG row and PG failure stays unknown" do
    State.put_registration_enabled(ScratchRepo, true)

    for value <- [false, nil, true] do
      assert :ok = RegistrationSetting.put(value, ScratchRepo)
      assert {:ok, ^value} = RegistrationSetting.fetch(%{}, ScratchRepo)
      assert rows("SELECT enabled FROM phoenix.registration_setting") == [[value]]
    end

    rows("DELETE FROM phoenix.registration_setting")

    assert :error =
             RegistrationSetting.fetch(
               %{"ALLOW_EMAIL_PASSWORD_REGISTRATION" => "true"},
               ScratchRepo
             )

    assert {:error, :database} = RegistrationSetting.put(true, ScratchRepo)
    assert rows("SELECT enabled FROM phoenix.registration_setting") == []
    assert :error = RegistrationSetting.fetch(%{}, FailureRepo)
    assert {:error, :database} = RegistrationSetting.put(true, FailureRepo)
  end
end
