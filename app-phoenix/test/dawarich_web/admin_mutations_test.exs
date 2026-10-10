defmodule DawarichWeb.AdminMutationsTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.RailsUser
  alias Dawarich.Admin.Users

  defmodule RaceRepo do
    defdelegate transaction(fun), to: Dawarich.Repo
    defdelegate rollback(reason), to: Dawarich.Repo

    def query!(sql, params, opts) do
      if String.starts_with?(sql, "SELECT EXISTS(SELECT 1 FROM users WHERE email="),
        do: %{rows: [[false]]},
        else: Dawarich.Repo.query!(sql, params, opts)
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: 15011,
      email: "a10b-http-admin@example.invalid",
      admin: true,
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    RailsUser.insert!(%{
      id: 15012,
      email: "a10b-http-collision@example.invalid",
      deleted_at: ~N[2026-10-04 10:00:00]
    })

    previous = Application.get_env(:dawarich, Users)
    config = %{env: %{"SELF_HOSTED" => "true"}, clock: fn -> ~U[2026-10-04 10:00:00.000000Z] end}
    Application.put_env(:dawarich, Users, config)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, Users, previous),
        else: Application.delete_env(:dawarich, Users)
    end)

    %{scope: Scope.for_user(Accounts.get(15011), "en"), config: config}
  end

  test "returns Rails create validation failure without a row or effects", c do
    assert Code.ensure_loaded?(Users), "native admin users facade must exist"

    for {name, email, password} <- [
          {"duplicate_en", "a10b-http-collision@example.invalid", "a10b-create-password"},
          {"invalid_email", "invalid", "a10b-create-password"},
          {"short_password", "a10b-http-new@example.invalid", "short"}
        ] do
      before = snapshot()
      assert {:error, {:validation, message}} = Users.create(c.scope, input(email, password))
      oracle = File.read!("test/fixtures/admin_mutations/#{name}.json") |> Jason.decode!()
      assert message == oracle["flash"]["alert"]
      assert snapshot() == before
    end

    actor_before = Accounts.get(c.scope.user.id)

    assert {:ok, _} =
             Users.create(
               c.scope,
               input("a10b-http-created@example.invalid", "a10b-create-password")
             )

    assert Accounts.get(c.scope.user.id) == actor_before

    assert Repo.query!(
             "SELECT count(*) FROM users WHERE email=$1",
             ["a10b-http-created@example.invalid"],
             log: false
           ).rows == [[1]]

    before = snapshot()
    Application.put_env(:dawarich, Users, Map.put(c.config, :repo, RaceRepo))

    assert Users.create(
             c.scope,
             input("a10b-http-collision@example.invalid", "a10b-create-password")
           ) == {:error, :unavailable}

    assert snapshot() == before
  end

  defp input(email, password), do: %{"email" => email, "password" => password, "admin" => "1"}

  defp snapshot do
    Repo.query!(
      "SELECT (SELECT count(*) FROM users),(SELECT count(*) FROM job_outbox),(SELECT count(*) FROM oban.oban_jobs)",
      [],
      log: false
    ).rows
  end
end
