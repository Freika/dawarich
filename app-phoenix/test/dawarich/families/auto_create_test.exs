defmodule Dawarich.Families.AutoCreateTest do
  use Dawarich.JobsCase

  alias Dawarich.Families.AutoCreate

  @now ~U[2026-10-04 12:00:00Z]
  @until ~N[2026-10-05 12:00:00.000000]

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

  defp user!(settings \\ %{}, plan \\ 2, until \\ @until) do
    [[id]] =
      rows(
        "INSERT INTO users (email, settings, plan, active_until, created_at, updated_at) VALUES ($1, $2, $3, $4, now(), now()) RETURNING id",
        ["auto-family-#{System.unique_integer([:positive])}@example.test", settings, plan, until]
      )

    id
  end

  defp run(user, opts \\ []),
    do:
      AutoCreate.run(
        ScratchRepo,
        user,
        Keyword.merge([now: @now, time_zone: "Europe/Berlin"], opts)
      )

  defp settings(user),
    do: rows("SELECT settings FROM users WHERE id = $1", [user]) |> hd() |> hd()

  defp sharing(user), do: settings(user)["family"]["location_sharing"]

  defp counts(user),
    do:
      rows(
        "SELECT (SELECT count(*) FROM families WHERE creator_id = $1), (SELECT count(*) FROM family_memberships WHERE user_id = $1), (SELECT count(*) FROM notifications WHERE user_id = $1)",
        [user]
      )
      |> hd()

  test "source-handled family and membership insert failures complete without partial rows or retry" do
    for table <- ["families", "family_memberships"] do
      user = user!()
      event = Ecto.UUID.generate()
      rows("ALTER TABLE #{table} ADD CONSTRAINT a12d2_creation_failure CHECK (false) NOT VALID")

      try do
        log =
          ExUnit.CaptureLog.capture_log(fn ->
            assert Dawarich.Families.AutoCreateWorker.run(
                     ScratchRepo,
                     %{"user_id" => user, "time_zone" => "Europe/Berlin", "event_id" => event},
                     now: @now
                   ) == :ok
          end)

        assert log =~ "Family creation failed: Postgrex.Error"
        assert Dawarich.Jobs.Processed.done?(ScratchRepo, event)
        assert counts(user) == [0, 0, 0]
        assert settings(user) == %{}
      after
        rows("ALTER TABLE #{table} DROP CONSTRAINT a12d2_creation_failure")
      end
    end
  end

  test "eligible Cloud owner gets one localised family membership and source sharing defaults" do
    user = user!(%{"locale" => " DE ", "sentinel" => true, "timezone" => "Asia/Tokyo"})
    assert run(user) == true

    assert rows("SELECT name, access_until FROM families WHERE creator_id = $1", [user]) == [
             ["Meine Familie", @until]
           ]

    assert counts(user) == [1, 1, 1]
    assert rows("SELECT role FROM family_memberships WHERE user_id = $1", [user]) == [[0]]
    assert settings(user)["sentinel"] == true

    assert sharing(user) == %{
             "enabled" => true,
             "started_at" => "2026-10-04T14:00:00+02:00",
             "share_history" => false,
             "history_before_sharing" => false,
             "history_window" => "7d"
           }

    assert rows("SELECT kind, title, content FROM notifications WHERE user_id = $1", [user]) == [
             [
               0,
               "Dein Family-Tarif ist bereit",
               "Wir haben \"Meine Familie\" für dich eingerichtet. Lade bis zu 4 Personen ein und ihr seht euch auf der Karte."
             ]
           ]

    assert rows("SELECT count(*) FROM phoenix.notification_events") == [[1]]
    assert run(user) == false
    assert counts(user) == [1, 1, 1]

    old = %{
      "enabled" => false,
      "started_at" => "retained",
      "share_history" => true,
      "history_before_sharing" => true,
      "history_window" => "30d",
      "duration" => "12h",
      "expires_at" => "2026-10-04T15:00:00+02:00",
      "discarded" => true
    }

    retained =
      user!(%{"family" => %{"location_sharing" => old, "sentinel" => true}, "sentinel" => true})

    assert run(retained) == true
    assert sharing(retained) == old |> Map.delete("discarded") |> Map.put("enabled", true)
    assert settings(retained)["family"]["sentinel"] == true

    for {history, consent, expected} <- [
          {true, false, false},
          {false, true, false},
          {nil, true, false}
        ] do
      id =
        user!(%{
          "family" => %{
            "location_sharing" => %{
              "share_history" => history,
              "history_before_sharing" => consent,
              "history_window" => "invalid",
              "duration" => "12",
              "expires_at" => "invalid"
            }
          }
        })

      assert run(id, time_zone: "UTC") == true
      assert sharing(id)["history_before_sharing"] == expected
      assert sharing(id)["history_window"] == "7d"
      assert sharing(id)["expires_at"] == "2026-10-05T00:00:00+00:00"
    end

    expired = user!(%{}, 2, nil)
    assert run(expired) == true
    assert rows("SELECT access_until FROM families WHERE creator_id = $1", [expired]) == [[nil]]
    lite = user!(%{}, 0)
    pro = user!(%{}, 1)
    deleted = user!()
    rows("UPDATE users SET deleted_at = now() WHERE id = $1", [deleted])
    for id <- [lite, pro, deleted, -1], do: assert(run(id) == false)
    member = user!()
    [[family]] = rows("SELECT id FROM families WHERE creator_id = $1", [user])

    rows(
      "INSERT INTO family_memberships (family_id, user_id, created_at, updated_at) VALUES ($1, $2, now(), now())",
      [family, member]
    )

    assert run(member) == false
    creator = user!()

    rows(
      "INSERT INTO families (name, creator_id, created_at, updated_at) VALUES ('Existing', $1, now(), now())",
      [creator]
    )

    assert run(creator) == false
    System.put_env("SELF_HOSTED", "true")
    hosted = user!()
    assert run(hosted) == false
    assert counts(hosted) == [0, 0, 0]
  end

  test "failed creation rolls back and concurrent replay cannot create a second family" do
    user = user!()

    hook = fn
      :joined -> ScratchRepo.query!("SELECT 1 / 0", [], log: false)
      _ -> :ok
    end

    assert_raise Postgrex.Error, fn -> run(user, hook: hook) end
    assert counts(user) == [0, 0, 0]
    assert settings(user) == %{}
    parent = self()

    first =
      Task.async(fn ->
        run(user,
          hook: fn
            :locked ->
              send(parent, {:locked, self()})

              receive do
                :continue -> :ok
              end

            _ ->
              :ok
          end
        )
      end)

    assert_receive {:locked, holder}
    second = Task.async(fn -> run(user) end)
    assert Dawarich.LockRace.settle(second, "SELECT plan, settings FROM users%") == :blocked
    send(holder, :continue)
    assert Task.await(first) == true
    assert Task.await(second) == false
    assert counts(user) == [1, 1, 1]
  end

  test "notification failure keeps successful family but sync failure keeps none" do
    user = user!()
    rows("ALTER TABLE notifications ADD CONSTRAINT a12d2_notice_failure CHECK (false) NOT VALID")

    try do
      assert run(user) == true
    after
      rows("ALTER TABLE notifications DROP CONSTRAINT a12d2_notice_failure")
    end

    assert counts(user) == [1, 1, 0]
    assert sharing(user)["enabled"] == true
    assert rows("SELECT count(*) FROM phoenix.notification_events") == [[0]]
    failing = user!()

    hook = fn
      :shared -> ScratchRepo.query!("SELECT 1 / 0", [], log: false)
      _ -> :ok
    end

    assert_raise Postgrex.Error, fn -> run(failing, hook: hook) end
    assert counts(failing) == [0, 0, 0]
    assert settings(failing) == %{}
    assert run(failing) == true
    assert counts(failing) == [1, 1, 1]
  end
end
