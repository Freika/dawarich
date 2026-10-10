defmodule DawarichWeb.AdminSettingWritesTest do
  use ExUnit.Case, async: false
  alias Dawarich.Admin.SettingWrites
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser

  defmodule RegistrationFailureRepo do
    def query!(sql, params, opts), do: Dawarich.Repo.query!(sql, params, opts)

    def transaction(_) do
      send(self(), :registration_sql_attempt)
      raise DBConnection.ConnectionError, message: "synthetic registration SQL refusal"
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: 15511,
      email: "a10b-instance-http@example.invalid",
      admin: true,
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    %{context: %{self_hosted: true, oidc: false, env: %{}, command: fn _ -> {:ok, 0} end}}
  end

  test "denied admin update and failed PG write preserve the registration state", c do
    Dawarich.State.put_registration_enabled(Repo, true)
    RailsUser.insert!(%{id: 15512, email: "a13g-denied-member@example.invalid"})
    member = Dawarich.Accounts.get(15512)
    admin = Dawarich.Accounts.get(15511)

    assert {:handoff, :actor} =
             SettingWrites.registration(member, %{"registration_enabled" => "0"}, c.context)

    assert {:handoff, :cloud} =
             SettingWrites.registration(admin, %{}, %{c.context | self_hosted: false})

    assert {:handoff, :oidc} = SettingWrites.registration(admin, %{}, %{c.context | oidc: true})

    assert {:terminal, _} =
             SettingWrites.registration(
               admin,
               %{"registration_enabled" => "0"},
               Map.put(c.context, :repo, RegistrationFailureRepo)
             )

    assert_received :registration_sql_attempt

    assert Repo.query!("SELECT enabled FROM phoenix.registration_setting", [], log: false).rows ==
             [[true]]
  end
end
