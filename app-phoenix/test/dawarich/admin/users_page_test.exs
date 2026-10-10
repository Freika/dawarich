defmodule Dawarich.Admin.UsersPageTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Accounts, Redis, Repo}
  alias Dawarich.Admin.UsersPage
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    start_supervised!(hd(Redis.cache_child_specs()))
    Dawarich.State.put_registration_enabled(Repo, true)
    original = System.get_env("ALLOW_EMAIL_PASSWORD_REGISTRATION")
    System.put_env("ALLOW_EMAIL_PASSWORD_REGISTRATION", "true")

    on_exit(fn ->
      if original,
        do: System.put_env("ALLOW_EMAIL_PASSWORD_REGISTRATION", original),
        else: System.delete_env("ALLOW_EMAIL_PASSWORD_REGISTRATION")
    end)

    state = fixture("list")
    for row <- state["rows"], do: insert!(row)

    RailsUser.insert!(%{
      id: 10999,
      email: "deleted-sentinel@example.invalid",
      deleted_at: ~N[2026-10-03 10:00:00],
      created_at: ~N[2026-10-03 10:00:00]
    })

    {:ok, actor: Accounts.get(10001)}
  end

  test "users search escapes wildcards and excludes soft deleted accounts", %{actor: actor} do
    RailsUser.insert!(%{
      id: 10880,
      email: "other-underscore_@example.invalid",
      created_at: ~N[2026-09-01 09:00:00]
    })

    assert {:ok, result} = list(actor, %{"search" => "%_"})
    assert Enum.map(result.rows, & &1.id) == fixture("list_literal")["visible_ids"]
    assert {:ok, result} = list(actor, %{})
    refute 10999 in Enum.map(result.rows, & &1.id)

    RailsUser.insert!(%{
      id: 10888,
      email: "back\\slash@example.invalid",
      created_at: ~N[2026-09-01 10:00:00]
    })

    assert {:ok, result} = list(actor, %{"search" => "back\\slash"})
    assert Enum.map(result.rows, & &1.id) == [10888]
    refute Enum.any?(result.rows, &Map.has_key?(&1, :api_key))
    assert {:ok, empty} = list(actor, %{"search" => "no-match"})
    assert empty.rows == []
  end

  test "users pagination is 25 rows with newest created first", %{actor: actor} do
    for {name, query} <- [
          {"list", %{}},
          {"list_page2", %{"page" => "2"}},
          {"list_out", %{"page" => "3"}}
        ] do
      assert {:ok, result} = list(actor, query)
      assert Enum.map(result.rows, & &1.id) == fixture(name)["visible_ids"]
      assert result.pages == 2
    end

    assert {:ok, first} = list(actor, %{"page" => "garbage"})
    assert first.page == 1
    assert {:error, :invalid_input} == list(actor, %{"page" => "999999999999999999999"})
  end

  test "tied users paginate in descending id order without overlap", %{actor: actor} do
    Repo.query!("UPDATE users SET created_at='2026-10-03 10:00:00' WHERE deleted_at IS NULL", [],
      log: false
    )

    assert {:ok, first} = list(actor, %{})
    assert {:ok, second} = list(actor, %{"page" => "2"})
    ids = Enum.map(first.rows ++ second.rows, & &1.id)

    expected =
      Repo.query!("SELECT id FROM users WHERE deleted_at IS NULL ORDER BY id DESC", [],
        log: false
      ).rows
      |> List.flatten()

    assert ids == expected
    assert length(Enum.uniq(ids)) == length(ids)
  end

  test "user detail counts and timestamps belong to target but zone belongs to actor", %{
    actor: actor
  } do
    row = fixture("show_target")["target"]

    Repo.query!(
      "UPDATE users SET api_key = $1, sign_in_count = $2, last_sign_in_ip = $3, current_sign_in_ip = $4 WHERE id = 10002",
      [row["api_key"], row["sign_in_count"], row["last_sign_in_ip"], row["current_sign_in_ip"]],
      log: false
    )

    for table <- ~w(imports exports),
        do:
          Repo.insert_all(table, [
            %{
              id: 10001,
              user_id: 10002,
              name: "Synthetic",
              created_at: ~N[2026-10-03 10:00:00],
              updated_at: ~N[2026-10-03 10:00:00]
            }
          ])

    Repo.query!(
      "INSERT INTO tracks(id, user_id, start_at, end_at, original_path, created_at, updated_at) VALUES(10001,10002,'2026-10-03 09:00:00','2026-10-03 10:00:00',ST_GeomFromText('LINESTRING(0 0,0.001 0.001)',4326),'2026-10-03 10:00:00','2026-10-03 10:00:00')",
      [],
      log: false
    )

    Repo.insert_all("areas", [
      %{
        id: 10001,
        user_id: 10002,
        name: "Synthetic",
        radius: 100,
        latitude: 0.0,
        longitude: 0.0,
        created_at: ~N[2026-10-03 10:00:00],
        updated_at: ~N[2026-10-03 10:00:00]
      }
    ])

    assert {:ok, target} = find(actor, 10002, :show)
    assert target.counts == row["counts"]
    assert target.last_sign_in_at.local == ~N[2026-10-03 10:00:00.000000]
    assert target.last_sign_in_at.offset == 7200
    assert target.api_key == row["api_key"]
    assert target.last_sign_in_ip == "192.0.2.10"
    assert target.current_sign_in_ip == "192.0.2.20"
    assert {:ok, edit} = find(actor, 10002, :edit)
    refute Map.has_key?(edit, :api_key)
    assert {:error, :not_found} == find(actor, 10999, :show)
    assert {:error, :not_found} == find(actor, 99999, :edit)
    Repo.query!("UPDATE users SET api_key = '' WHERE id = 10002", [], log: false)
    assert {:error, :unavailable} == find(actor, 10002, :show)
  end

  test "stored nil renders disabled without rewriting policy", %{actor: actor} do
    bytes = Dawarich.RailsCache.Wire.encode_boolean(true, expires_at: nil)
    assert {:ok, "OK"} = Redis.cache_command(["SET", "dawarich/registration_enabled", bytes])

    for value <- [false, true, nil] do
      Dawarich.State.put_registration_enabled(Repo, value)
      assert {:ok, result} = list(actor, %{})
      assert result.registration == value

      assert Repo.query!("SELECT enabled FROM phoenix.registration_setting", [], log: false).rows ==
               [[value]]
    end
  end

  test "missing registration row refuses without a permissive default", %{actor: actor} do
    Repo.query!("DELETE FROM phoenix.registration_setting", [], log: false)
    assert {:error, :unavailable} = list(actor, %{})

    assert Repo.query!("SELECT count(*) FROM phoenix.registration_setting", [], log: false).rows ==
             [[0]]
  end

  test "users page normalizes scalar pages and refuses malformed inputs", %{actor: actor} do
    for page <- [nil, "", "garbage", "-8", "0"] do
      assert {:ok, %{page: 1}} = list(actor, %{"page" => page})
    end

    for query <- [%{"page" => []}, %{"search" => %{}}, %{"page" => "999999999999999999999"}] do
      assert {:error, :invalid_input} = list(actor, query)
    end

    assert {:error, :not_found} = find(actor, "oops", :edit)
  end

  defp list(actor, query), do: UsersPage.list(actor, query)
  defp find(actor, id, kind), do: UsersPage.find(actor, id, kind)

  defp fixture(name), do: Jason.decode!(File.read!("test/fixtures/admin_users/#{name}.json"))

  defp insert!(row) do
    RailsUser.insert!(%{
      id: row["id"],
      email: row["email"],
      admin: row["admin"],
      settings: row["settings"],
      status: row["status"],
      points_count: row["points_count"],
      created_at: naive(row["created_at"]),
      last_sign_in_at: naive(row["last_sign_in_at"])
    })
  end

  defp naive(nil), do: nil
  defp naive(value), do: value |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()
end
