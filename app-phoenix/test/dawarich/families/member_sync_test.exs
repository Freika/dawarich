defmodule Dawarich.Families.MemberSyncTest do
  use Dawarich.JobsCase

  alias Dawarich.Families.MemberSync
  alias Dawarich.Jobs.Ownership

  @now ~U[2026-10-04 12:00:00Z]
  @future ~N[2026-10-05 12:00:00.000000]
  @past ~N[2026-10-03 12:00:00.000000]

  setup do
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    :ok
  end

  defp user!(opts) do
    [[id]] =
      rows(
        "INSERT INTO users (email, plan, status, active_until, subscription_source, settings, created_at, updated_at) " <>
          "VALUES ($1, $2, $3, $4, $5, $6, now(), now()) RETURNING id",
        [
          "family-sync-#{System.unique_integer([:positive])}@example.test",
          Keyword.get(opts, :plan, 0),
          Keyword.get(opts, :status, 0),
          opts[:until],
          Keyword.get(opts, :source, 0),
          Keyword.get(opts, :settings, %{})
        ]
      )

    id
  end

  defp family!(owner, until) do
    [[id]] =
      rows(
        "INSERT INTO families (name, creator_id, access_until, created_at, updated_at) VALUES ('Synthetic family', $1, $2, now(), now()) RETURNING id",
        [owner, until]
      )

    member!(id, owner, 0)
    id
  end

  defp member!(family, user, role \\ 1),
    do:
      rows(
        "INSERT INTO family_memberships (family_id, user_id, role, created_at, updated_at) VALUES ($1, $2, $3, now(), now())",
        [family, user, role]
      )

  defp add!(family, opts \\ []) do
    id = user!(opts)
    member!(family, id)
    id
  end

  defp state(id),
    do:
      rows(
        "SELECT plan, status, active_until, subscription_source, settings FROM users WHERE id = $1",
        [id]
      )
      |> hd()

  defp paid(family),
    do: rows("SELECT access_until FROM families WHERE id = $1", [family]) |> hd() |> hd()

  defp outbox,
    do:
      rows(
        "SELECT command_type, payload, dedupe_key FROM public.job_outbox ORDER BY scheduled_at"
      )

  defp reverse, do: rows("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id")

  defp run(family, opts \\ []),
    do:
      MemberSync.run(
        ScratchRepo,
        family,
        [now: @now, locale: "de", time_zone: "Europe/Berlin"] ++ opts
      )

  test "sync retains paid periods and skips creator and own-live subscriptions" do
    owner = user!(plan: 2, status: 2, until: @future, source: 1)
    family = family!(owner, @past)
    owner_before = state(owner)
    inherited = add!(family, source: 1, status: 1, until: @past)
    own = add!(family, plan: 1, source: 2, status: 2, until: @future)
    own_before = state(own)
    pending = add!(family, source: 3, status: 3, until: @future)
    assert run(family) == true
    assert paid(family) == @future
    for id <- [inherited, pending], do: assert(Enum.take(state(id), 4) == [1, 1, @future, 0])
    assert state(owner) == owner_before
    assert state(own) == own_before

    rows("UPDATE users SET plan = 1, active_until = $2 WHERE id = $1", [
      owner,
      ~N[2026-11-04 12:00:00]
    ])

    assert run(family) == true
    assert paid(family) == @future
    rows("UPDATE users SET active_until = NULL WHERE id = $1", [owner])
    assert run(family) == true
    assert paid(family) == @future
    rows("UPDATE users SET deleted_at = now() WHERE id = $1", [owner])
    assert run(family) == true
    assert paid(family) == @future
    rows("UPDATE users SET deleted_at = NULL, active_until = $2 WHERE id = $1", [owner, @past])
    assert run(family, notify: false) == true
    assert paid(family) == @past
    assert Enum.take(state(inherited), 4) == [0, 0, @past, 0]
    nil_owner = user!(plan: 1, until: @future)
    nil_family = family!(nil_owner, nil)
    nil_member = add!(nil_family)
    assert run(nil_family, notify: false) == true
    assert paid(nil_family) == nil
    assert Enum.take(state(nil_member), 4) == [0, 0, nil, 0]
    assert run(-1) == false
    System.put_env("SELF_HOSTED", "true")
    before = state(inherited)
    assert run(family) == false
    assert state(inherited) == before
  end

  test "grant clears lapse marker and lapse publishes source mail once with leaf owner" do
    Ownership.put!(ScratchRepo, "command:mail.family_lapse", :oban)
    owner = user!(plan: 2, until: @past)
    family = family!(owner, @past)

    settings = %{
      "unrelated" => "keep",
      "family" => %{"sentinel" => true, "plan_lapse_notified_at" => "already"}
    }

    notified = add!(family, settings: settings, source: 1)

    due =
      add!(family, plan: 1, source: 3, status: 0, until: @past, settings: %{"sentinel" => true})

    payload = %{
      "user_id" => due,
      "family_id" => family,
      "locale" => "de",
      "lapse_at" => "2026-10-03T12:00:00Z"
    }

    assert run(family) == true
    assert state(notified) == [0, 0, @past, 1, settings]
    assert Enum.take(state(due), 4) == [0, 0, @past, 3]

    assert outbox() == [
             ["mail.family_lapse", payload, "family-lapse:#{family}:#{due}:2026-10-03T12:00:00Z"]
           ]

    assert run(family) == true
    assert length(outbox()) == 1
    assert reverse() == []
    rows("UPDATE users SET active_until = $2 WHERE id = $1", [owner, @future])
    assert run(family) == true

    assert state(notified) == [
             1,
             1,
             @future,
             0,
             %{"unrelated" => "keep", "family" => %{"sentinel" => true}}
           ]

    rows("DELETE FROM public.job_outbox")
    rows("UPDATE users SET active_until = $2 WHERE id = $1", [owner, @past])
    assert run(family, notify: false) == true
    assert outbox() == []

    assert Enum.at(state(due), 4)["family"]["plan_lapse_notified_at"] ==
             "2026-10-04T14:00:00+02:00"

    assert run(family) == true
    assert outbox() == []

    rows(
      "UPDATE users SET settings = settings #- '{family,plan_lapse_notified_at}' WHERE id = $1",
      [due]
    )

    Ownership.put!(ScratchRepo, "command:mail.family_lapse", :sidekiq)
    assert run(family) == true
    assert reverse() == [["mail.family_lapse", payload]]
    assert outbox() == []
  end

  test "failed member write rolls all entitlement and notice effects back" do
    Ownership.put!(ScratchRepo, "command:mail.family_lapse", :oban)
    owner = user!(plan: 2, until: @past)
    family = family!(owner, @future)
    first = add!(family, plan: 1, status: 1, until: @future)
    failing = add!(family, plan: 1, status: 1, until: @future)
    before = [state(first), state(failing), paid(family)]

    hook = fn
      ^failing -> ScratchRepo.query!("SELECT 1 / 0", [], log: false)
      _ -> :ok
    end

    assert_raise Postgrex.Error, fn -> run(family, hook: hook) end
    assert [state(first), state(failing), paid(family)] == before
    assert outbox() == []
    assert reverse() == []
    assert run(family) == true
    assert Enum.take(state(first), 4) == [0, 0, @past, 0]
    assert length(outbox()) == 2
  end
end
