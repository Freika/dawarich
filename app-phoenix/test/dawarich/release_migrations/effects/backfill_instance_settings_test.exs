defmodule Dawarich.ReleaseMigrations.Effects.BackfillInstanceSettingsTest do
  use Dawarich.ScratchCase

  import Dawarich.GeocodingFixtures

  alias Dawarich.ReleaseMigrations.Effects.BackfillInstanceSettings
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.ReleaseMigrations.V1_15_0

  setup :create_tables

  test "copies every set variable with the registry's coercions and encrypts the secrets" do
    BackfillInstanceSettings.run(
      ScratchRepo,
      env(%{
        "PHOTON_API_HOST" => " photon.example.test ",
        "PHOTON_API_KEY" => "schema-parity-env-photon-key",
        "PHOTON_API_USE_HTTPS" => "false",
        "NOMINATIM_API_USE_HTTPS" => "TRUE",
        "REVERSE_GEOCODING_RPS" => "0x1.8p1",
        "STORE_GEODATA" => " \t\n\v\f\r",
        "LOCATIONIQ_API_KEY" => ""
      })
    )

    assert instance_settings() == [
             {"photon_api_host", "photon.example.test"},
             {"photon_api_key", {:secret, "schema-parity-env-photon-key"}},
             {"photon_api_use_https", false},
             {"nominatim_api_use_https", false},
             {"reverse_geocoding_rps", 3.0}
           ]
  end

  test "stores an rps Ruby reads as Infinity as JSON null and skips one it cannot read" do
    BackfillInstanceSettings.run(ScratchRepo, env(%{"REVERSE_GEOCODING_RPS" => "1e400"}))
    assert instance_settings() == [{"reverse_geocoding_rps", nil}]
    assert raw_value("reverse_geocoding_rps") == "null"

    Dawarich.ScratchRepo.query!("TRUNCATE instance_settings")
    BackfillInstanceSettings.run(ScratchRepo, env(%{"REVERSE_GEOCODING_RPS" => "fast"}))
    assert instance_settings() == []
  end

  test "an environment provider wins over a conflicting administrator setting" do
    admin = user("admin@example.test", admin: true)
    user("member@example.test")

    setting(admin, "photon", %{"host" => "photon.admin.test", "use_https" => true, "rps" => 2},
      credentials: encrypted(~s({"api_key":"schema-parity-admin-key"})),
      active: true
    )

    BackfillInstanceSettings.run(
      ScratchRepo,
      env(%{"GEOAPIFY_API_KEY" => "schema-parity-env-key"})
    )

    assert instance_settings() == [{"geoapify_api_key", {:secret, "schema-parity-env-key"}}]
  end

  test "copies a unanimous user configuration, keeping use_https false and the lowest rate" do
    for {email, rps} <- [
          {"a@example.test", 5},
          {"b@example.test", "2"},
          {"c@example.test", 2},
          {"d@example.test", nil}
        ] do
      config =
        if rps,
          do: %{"host" => "photon.example.test", "use_https" => false, "rps" => rps},
          else: %{"host" => "photon.example.test", "use_https" => false}

      setting(user(email), "photon", config, active: true)
    end

    user("gone@example.test", deleted: true)
    BackfillInstanceSettings.run(ScratchRepo, env())

    assert instance_settings() == [
             {"photon_api_host", "photon.example.test"},
             {"photon_api_use_https", false},
             {"reverse_geocoding_rps", "2"}
           ]
  end

  test "copies a unanimous nominatim configuration with its host, key and use_https" do
    key = encrypted(~s({"api_key":"schema-parity-nominatim-key"}))

    for email <- ["a@example.test", "b@example.test"] do
      setting(
        user(email),
        "nominatim",
        %{"host" => "nominatim.example.test", "use_https" => false},
        credentials: key,
        active: true
      )
    end

    BackfillInstanceSettings.run(ScratchRepo, env())

    assert instance_settings() == [
             {"nominatim_api_host", "nominatim.example.test"},
             {"nominatim_api_key", {:secret, "schema-parity-nominatim-key"}},
             {"nominatim_api_use_https", false}
           ]
  end

  test "copies the administrators' configuration when users disagree and administrators agree" do
    setting(user("a@example.test"), "photon", %{"host" => "photon.a.test"}, active: true)
    setting(user("b@example.test"), "nominatim", %{"host" => "nominatim.b.test"}, active: true)
    key = encrypted(~s({"api_key":"schema-parity-admin-key"}))

    for {email, rps} <- [{"admin-a@example.test", 1.5}, {"admin-b@example.test", 0.5}] do
      setting(
        user(email, admin: true),
        "photon",
        %{"host" => "photon.admin.test", "use_https" => true, "rps" => rps},
        credentials: key,
        active: true
      )
    end

    BackfillInstanceSettings.run(ScratchRepo, env())

    assert instance_settings() == [
             {"photon_api_host", "photon.admin.test"},
             {"photon_api_key", {:secret, "schema-parity-admin-key"}},
             {"photon_api_use_https", true},
             {"reverse_geocoding_rps", 0.5}
           ]
  end

  test "writes nothing when users and administrators disagree, or when some users have no setting" do
    setting(user("a@example.test"), "photon", %{"host" => "photon.a.test"}, active: true)

    setting(user("admin-a@example.test", admin: true), "photon", %{"host" => "photon.a.test"},
      active: true
    )

    setting(
      user("admin-b@example.test", admin: true),
      "nominatim",
      %{"host" => "nominatim.c.test"},
      active: true
    )

    BackfillInstanceSettings.run(ScratchRepo, env())
    assert instance_settings() == []

    Dawarich.ScratchRepo.query!("TRUNCATE service_settings, users CASCADE")

    setting(user("covered@example.test"), "geoapify", %{},
      credentials: encrypted(~s({"api_key":"k"})),
      active: true
    )

    setting(user("uncovered@example.test"), "photon", %{"host" => "photon.example.test"})

    BackfillInstanceSettings.run(ScratchRepo, env())
    assert instance_settings() == []
  end

  test "never overwrites a key the environment already stored" do
    setting(
      user("a@example.test"),
      "photon",
      %{"host" => "photon.user.test", "use_https" => true, "rps" => 7},
      credentials: encrypted(~s({"api_key":"schema-parity-user-key"})),
      active: true
    )

    BackfillInstanceSettings.run(
      ScratchRepo,
      env(%{
        "PHOTON_API_KEY" => "schema-parity-env-key",
        "PHOTON_API_USE_HTTPS" => "false",
        "REVERSE_GEOCODING_RPS" => "4"
      })
    )

    assert instance_settings() == [
             {"photon_api_key", {:secret, "schema-parity-env-key"}},
             {"photon_api_use_https", false},
             {"reverse_geocoding_rps", 4.0},
             {"photon_api_host", "photon.user.test"}
           ]
  end

  test "never promotes a key it cannot decrypt, but still copies the rest of an agreeing configuration" do
    unreadable = flipped_tag(~s({"api_key":"k"}))

    for email <- ["a@example.test", "b@example.test"] do
      setting(
        user(email),
        "photon",
        %{"host" => "photon.example.test", "use_https" => true, "rps" => 3},
        credentials: unreadable,
        active: true
      )
    end

    BackfillInstanceSettings.run(ScratchRepo, env())

    assert instance_settings() == [
             {"photon_api_host", "photon.example.test"},
             {"photon_api_use_https", true},
             {"reverse_geocoding_rps", 3}
           ]
  end

  test "fails the step where Rails raises: a malformed key or missing encryption keys" do
    setting(user("a@example.test"), "geoapify", %{}, credentials: string_headers(), active: true)

    assert_raise Ruby.Error, "undefined method 'each' for an instance of String", fn ->
      BackfillInstanceSettings.run(ScratchRepo, env())
    end

    Dawarich.ScratchRepo.query!("TRUNCATE service_settings, users CASCADE")

    assert_raise Ruby.Error,
                 "Missing Active Record encryption credential: active_record_encryption.primary_key",
                 fn ->
                   BackfillInstanceSettings.run(
                     ScratchRepo,
                     env(%{
                       "OTP_ENCRYPTION_PRIMARY_KEY" => "",
                       "PHOTON_API_HOST" => "photon.example.test",
                       "PHOTON_API_KEY" => "k"
                     })
                   )
                 end
  end

  test "writes floats the way Oj's Rails encoder formats them" do
    BackfillInstanceSettings.run(ScratchRepo, env(%{"REVERSE_GEOCODING_RPS" => "0.00005"}))
    assert raw_value("reverse_geocoding_rps") == "0.00005"

    Dawarich.ScratchRepo.query!("TRUNCATE instance_settings")

    for email <- ["a@example.test", "b@example.test"] do
      setting(
        user(email),
        "photon",
        %{"host" => "photon.example.test", "rps" => 0.30000000000000004},
        active: true
      )
    end

    BackfillInstanceSettings.run(ScratchRepo, env())
    assert raw_value("reverse_geocoding_rps") == "0.3"
  end

  test "fails the step on decrypted credentials that are not UTF-8, as Ruby's blank? does" do
    setting(user("a@example.test"), "geoapify", %{},
      credentials: encrypted(<<0xFF>>),
      active: true
    )

    assert_raise Ruby.Error, "invalid byte sequence in UTF-8", fn ->
      BackfillInstanceSettings.run(ScratchRepo, env())
    end
  end

  test "fails the step on credentials Oj might parse and Jason cannot, and skips ones Oj rejects too" do
    setting(user("a@example.test"), "geoapify", %{},
      credentials: encrypted(~s({"api_key":"k" // comment\n})),
      active: true
    )

    assert_raise Ruby.Unreproducible, ~r/Oj's JSON.parse may accept/, fn ->
      BackfillInstanceSettings.run(ScratchRepo, env())
    end

    Dawarich.ScratchRepo.query!("UPDATE service_settings SET credentials = $1", [
      encrypted("not json")
    ])

    BackfillInstanceSettings.run(ScratchRepo, env())

    assert instance_settings() == []
  end

  test "the 20260901150000 step runs the backfill" do
    {_, step, _} =
      V1_15_0.steps()
      |> Enum.map(&Dawarich.ReleaseMigration.normalize/1)
      |> List.keyfind("20260901150000", 0)

    with_env(env(%{"PHOTON_API_HOST" => "photon.example.test"}), fn -> step.(ScratchRepo) end)

    assert instance_settings() == [{"photon_api_host", "photon.example.test"}]
  end

  defp raw_value(key) do
    Dawarich.ScratchRepo.query!("SELECT value::text FROM instance_settings WHERE key = $1", [key]).rows
    |> List.first()
    |> List.first()
  end
end
