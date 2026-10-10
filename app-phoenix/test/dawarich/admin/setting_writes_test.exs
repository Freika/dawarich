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

  test "admin registration casts persist true false nil in the caller repo", c do
    Dawarich.JobsCase.reset!(Dawarich.ScratchRepo)

    RailsUser.insert!(
      %{id: c.admin.id, email: "a13g-scratch-admin@example.invalid", admin: true},
      Dawarich.ScratchRepo
    )

    Dawarich.State.put_registration_enabled(Repo, false)
    Dawarich.State.put_registration_enabled(Dawarich.ScratchRepo, true)
    context = Map.put(c.context, :repo, Dawarich.ScratchRepo)
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)
    {:ok, original} = Redis.cache_command(["GET", @key])
    bytes = Wire.encode_boolean(true, expires_at: nil)

    try do
      assert {:ok, "OK"} = Redis.cache_command(["SET", @key, bytes])

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
                 SettingWrites.registration(c.admin, %{"registration_enabled" => input}, context)

        assert {:ok, ^value} = RegistrationSetting.fetch(%{}, Dawarich.ScratchRepo)

        assert Repo.query!("SELECT enabled FROM phoenix.registration_setting", [], log: false).rows ==
                 [[false]]

        assert {:ok, ^bytes} = Redis.cache_command(["GET", @key])
      end

      for value <- [true, false, nil] do
        assert {:ok, %{value: ^value, expires_at: 2_000_000_000.0}} =
                 Wire.decode(Wire.encode_boolean(value, expires_at: 2_000_000_000))
      end

      assert {:handoff, :actor} =
               SettingWrites.registration(c.member, %{"registration_enabled" => "1"}, c.context)

      assert {:handoff, :cloud} =
               SettingWrites.registration(c.admin, %{}, %{c.context | self_hosted: false})

      assert {:ok, ^bytes} = Redis.cache_command(["GET", @key])
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
