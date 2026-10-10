defmodule Dawarich.Admin.UserSecurityTest do
  use ExUnit.Case, async: false
  alias Dawarich.Accounts.Scope
  alias Dawarich.Admin.Users
  alias Dawarich.Admin.UserSecurity
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  @now ~U[2026-10-04 10:00:00.000000Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous = Application.get_env(:dawarich, Users)

    Application.put_env(:dawarich, Users, %{
      env: %{"SELF_HOSTED" => "true"},
      clock: fn -> @now end
    })

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, Users, previous),
        else: Application.delete_env(:dawarich, Users)
    end)

    RailsUser.insert!(%{
      id: 15301,
      email: "a10b-security-admin@example.invalid",
      admin: true,
      api_key: "synthetic-actor-key",
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    RailsUser.insert!(%{
      id: 15302,
      email: "a10b-security-target@example.invalid",
      api_key: "synthetic-target-key",
      settings: %{"immich_url" => "https://immich.example.invalid///"}
    })

    %{
      actor: Accounts.get(15301),
      context: %{self_hosted: true, oidc: false, locale: "en", clock: fn -> @now end}
    }
  end

  test "rotates the selected target key without changing actor credentials", c do
    assert Code.ensure_loaded?(UserSecurity), "target security actions must exist"
    before = snapshot(15301)
    target_before = snapshot(15302)
    assert {:ok, 15302} = UserSecurity.rotate(c.actor, 15302, c.context)
    target = snapshot(15302)

    key_valid =
      is_binary(target["api_key"]) and target["api_key"] =~ ~r/\A[0-9a-f]{64}\z/ and
        target["api_key"] != target_before["api_key"]

    assert key_valid
    assert target["settings"] == %{"immich_url" => "https://immich.example.invalid"}
    assert target["updated_at"] == "2026-10-04T10:00:00"
    actor_unchanged = snapshot(15301) == before
    assert actor_unchanged
    before = snapshot(15301)
    key_before = snapshot(15302)["api_key"]
    assert {:ok, 15302} = Users.rotate_api_key(Scope.for_user(c.actor, "en"), 15302)
    assert snapshot(15302)["api_key"] != key_before
    assert snapshot(15301) == before

    for field <-
          ~w(encrypted_password email admin status reset_password_token reset_password_sent_at) do
      same = target[field] == target_before[field]
      assert same
    end

    assert {:handoff, :target} = UserSecurity.rotate(c.actor, -1, c.context)

    Repo.query!("UPDATE users SET deleted_at=$1 WHERE id=15302", [DateTime.to_naive(@now)],
      log: false
    )

    before = snapshot(15302)
    assert {:handoff, :target} = UserSecurity.rotate(c.actor, 15302, c.context)
    assert snapshot(15302) == before

    Repo.query!(
      "UPDATE users SET deleted_at=NULL,settings=$1 WHERE id=15302",
      [%{"maps" => %{"url" => 5}}],
      log: false
    )

    before = snapshot(15302)
    assert {:handoff, :settings_callback} = UserSecurity.rotate(c.actor, 15302, c.context)
    assert snapshot(15302) == before
    Repo.query!("UPDATE users SET admin=false WHERE id=15301", [], log: false)
    assert {:handoff, :actor} = UserSecurity.rotate(c.actor, 15302, c.context)
  end

  test "issues targeted reset with existing digest and sealed mail atomically",
       c do
    assert Code.ensure_loaded?(UserSecurity), "target security actions must exist"

    for context <- [c.context, Map.put(c.context, :mail_deliverable, false)] do
      before = snapshot(15301)

      context =
        Map.put(context, :enqueue, fn notification ->
          send(self(), {:mail, notification})
          :ok
        end)

      assert {:ok, 15302} = UserSecurity.reset(c.actor, 15302, context)
      assert_received {:mail, %{}}
      assert is_binary(snapshot(15302)["reset_password_token"])
      assert snapshot(15301) == before
    end

    before = {snapshot(15301), snapshot(15302), jobs()}
    context = Map.put(c.context, :enqueue, fn _ -> {:error, :failed} end)
    assert {:terminal, :mail} = UserSecurity.reset(c.actor, 15302, context)
    assert {snapshot(15301), snapshot(15302), jobs()} == before
    assert {:handoff, :target} = UserSecurity.reset(c.actor, -1, c.context)

    source =
      File.read!("test/fixtures/admin_mutations/reset_mail_failure.json") |> Jason.decode!()

    assert source["after"]["reset_token_present"]
    assert source["error"] == "RuntimeError"
  end

  defp snapshot(id) do
    [[row]] = Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [id], log: false).rows
    row
  end

  defp jobs do
    Repo.query!(
      "SELECT (SELECT count(*) FROM job_outbox),(SELECT count(*) FROM oban.oban_jobs)",
      [],
      log: false
    ).rows
  end
end
