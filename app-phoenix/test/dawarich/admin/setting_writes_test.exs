defmodule Dawarich.Admin.SettingWritesTest do
  use ExUnit.Case, async: false
  alias Dawarich.Admin.SettingWrites
  alias Dawarich.Auth.RegistrationSetting
  alias Dawarich.RailsCache.Wire
  alias Dawarich.{Accounts, Redis, Repo}
  alias Dawarich.Test.RailsUser
  @now ~U[2026-10-04 10:00:00.000000Z]
  @key "dawarich/registration_enabled"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: 15401,
      email: "a10b-setting-admin@example.invalid",
      admin: true,
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    RailsUser.insert!(%{
      id: 15402,
      email: "a10b-setting-member@example.invalid",
      settings: %{
        "locale" => "en",
        "timezone" => "UTC",
        "unrelated" => "retained",
        "immich_url" => "https://immich.example.invalid///",
        "photoprism_url" => "https://photos.example.invalid/",
        "maps" => %{"url" => " https://maps.example.invalid "}
      }
    })

    %{
      admin: Accounts.get(15401),
      member: Accounts.get(15402),
      context: %{self_hosted: true, oidc: false, locale: "en", env: %{}, clock: fn -> @now end}
    }
  end

  test "writes source cast boolean readable by Rails and native registration fetch", c do
    assert Code.ensure_loaded?(SettingWrites), "admin setting writes must exist"
    assert Code.ensure_loaded?(Wire), "boolean cache encoder must exist"
    assert function_exported?(Wire, :encode_boolean, 2), "boolean cache encoder must exist"

    if is_nil(Process.whereis(Redis.Cache)),
      do:
        start_supervised!(
          {Redix, {System.fetch_env!("PHOENIX_TEST_REDIS_URL"), [name: Redis.Cache, database: 0]}}
        )

    {:ok, original} = Redis.cache_command(["GET", @key])

    try do
      for {input, value} <- [
            {"1", true},
            {"0", false},
            {"off", false},
            {"FALSE", false},
            {"false", false},
            {"yes", true},
            {"", nil},
            {nil, nil}
          ] do
        assert {:ok, ^value} =
                 SettingWrites.registration(
                   c.admin,
                   %{"registration_enabled" => input},
                   c.context
                 )

        {:ok, bytes} = Redis.cache_command(["GET", @key])
        assert is_binary(bytes), "shared Rails registration cache was not written"
        assert {:ok, %{value: ^value, expires_at: nil}} = Wire.decode(bytes)

        assert {:ok, ^value} =
                 RegistrationSetting.fetch(%{"ALLOW_EMAIL_PASSWORD_REGISTRATION" => "true"})

        assert Wire.encode_boolean(value, expires_at: nil) == bytes
      end

      for value <- [true, false, nil] do
        assert {:ok, %{value: ^value, expires_at: 2_000_000_000.0}} =
                 Wire.decode(Wire.encode_boolean(value, expires_at: 2_000_000_000))
      end

      {:ok, before} = Redis.cache_command(["GET", @key])

      assert {:handoff, :actor} =
               SettingWrites.registration(c.member, %{"registration_enabled" => "1"}, c.context)

      assert {:handoff, :cloud} =
               SettingWrites.registration(c.admin, %{}, %{c.context | self_hosted: false})

      assert {:ok, ^before} = Redis.cache_command(["GET", @key])
    after
      if original,
        do: Redis.cache_command(["SET", @key, original]),
        else: Redis.cache_command(["DEL", @key])
    end
  end

  test "nonadmin background write merges SafeSettings and preserves source strings", c do
    assert Code.ensure_loaded?(SettingWrites), "admin setting writes must exist"

    for value <- ["false", "true"] do
      assert {:ok, 15402} =
               SettingWrites.background(
                 c.member,
                 %{"visits_suggestions_enabled" => value},
                 c.context
               )

      [[settings]] = Repo.query!("SELECT settings FROM users WHERE id=15402", [], log: false).rows

      oracle =
        File.read!("test/fixtures/admin_setting_writes/background_query_#{value}.json")
        |> Jason.decode!()

      assert settings == oracle["after"]
    end

    Repo.query!("UPDATE users SET settings=$1 WHERE id=15402", [["nonobject"]], log: false)

    before = snapshot()

    assert {:handoff, :timezone_callback} =
             SettingWrites.background(
               c.member,
               %{"visits_suggestions_enabled" => "true"},
               c.context
             )

    assert snapshot() == before

    Repo.query!("UPDATE users SET settings=$1 WHERE id=15402", [%{"photoprism_url" => 5}],
      log: false
    )

    before = snapshot()

    assert {:handoff, :settings_callback} =
             SettingWrites.background(
               c.member,
               %{"visits_suggestions_enabled" => "true"},
               c.context
             )

    assert {:handoff, :cloud} =
             SettingWrites.background(c.member, %{}, %{c.context | self_hosted: false})

    assert snapshot() == before
  end

  defp snapshot,
    do: Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=15402", [], log: false).rows
end
