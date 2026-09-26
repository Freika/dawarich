defmodule Dawarich.ReleaseMigrations.Effects.SeedGeocodingFromEnvTest do
  use Dawarich.ScratchCase

  import Dawarich.GeocodingFixtures

  alias Dawarich.ReleaseMigrations.Effects.SeedGeocodingFromEnv
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.ReleaseMigrations.V1_13_1

  setup :create_tables

  @all_four %{
    "PHOTON_API_HOST" => "App.ChibiGeo.com/v1/photon/",
    "PHOTON_API_KEY" => " schema-parity-photon-key ",
    "PHOTON_API_USE_HTTPS" => "false",
    "GEOAPIFY_API_KEY" => "schema-parity-geoapify-key",
    "NOMINATIM_API_HOST" => "https://Nominatim.Example.Test:8080/",
    "NOMINATIM_API_KEY" => "schema-parity-nominatim-key",
    "NOMINATIM_API_USE_HTTPS" => "false",
    "LOCATIONIQ_API_KEY" => "schema-parity-locationiq-key"
  }

  test "creates every environment provider in chain order for each user and activates photon" do
    first = user("one@example.test")
    user("gone@example.test", deleted: true)
    second = user("two@example.test")

    seed(env(@all_four))

    expected = fn user_id ->
      [
        {user_id, "photon",
         %{"host" => "app.chibigeo.com/v1/photon", "use_https" => true, "rps" => 1.0},
         ~s({"api_key":"schema-parity-photon-key"}), true},
        {user_id, "geoapify", %{}, ~s({"api_key":"schema-parity-geoapify-key"}), false},
        {user_id, "nominatim", %{"host" => "nominatim.example.test:8080", "use_https" => false},
         ~s({"api_key":"schema-parity-nominatim-key"}), false},
        {user_id, "locationiq", %{}, ~s({"api_key":"schema-parity-locationiq-key"}), false}
      ]
    end

    assert settings() == expected.(first) ++ expected.(second)
  end

  test "activates the first provider of the chain that the user has" do
    geoapify_user = user("no-photon@example.test")

    seed(
      env(%{
        "GEOAPIFY_API_KEY" => "g",
        "NOMINATIM_API_HOST" => "nominatim.example.test",
        "LOCATIONIQ_API_KEY" => "l"
      })
    )

    assert active_providers() == [{geoapify_user, "geoapify"}]

    Dawarich.ScratchRepo.query!("TRUNCATE service_settings")
    seed(env(%{"NOMINATIM_API_HOST" => "nominatim.example.test", "LOCATIONIQ_API_KEY" => "l"}))

    assert active_providers() == [{geoapify_user, "nominatim"}]
  end

  test "never overwrites an existing provider and activates nothing for a user with an active one" do
    configured = user("configured@example.test")
    fresh = user("fresh@example.test")

    setting(configured, "nominatim", %{"host" => "nominatim.local", "use_https" => false},
      active: true
    )

    seed(
      env(%{
        "PHOTON_API_HOST" => "photon.example.test",
        "PHOTON_API_USE_HTTPS" => "true",
        "NOMINATIM_API_HOST" => "nominatim.example.test"
      })
    )

    photon = %{"host" => "photon.example.test", "use_https" => true}
    nominatim = %{"host" => "nominatim.example.test", "use_https" => true}

    assert settings() == [
             {configured, "nominatim", %{"host" => "nominatim.local", "use_https" => false}, nil,
              true},
             {configured, "photon", photon, nil, false},
             {fresh, "photon", photon, nil, true},
             {fresh, "nominatim", nominatim, nil, false}
           ]
  end

  test "does nothing when reverse geocoding is disabled, even with users and an inactive setting" do
    owner = user("disabled@example.test")
    setting(owner, "nominatim", %{"host" => "nominatim.example.test"})

    seed(
      env(%{"PHOTON_API_HOST" => "\u00A0", "PHOTON_API_KEY" => "k", "NOMINATIM_API_HOST" => ""})
    )

    assert active_providers() == []
    assert length(settings()) == 1
  end

  test "does nothing on Cloud" do
    user("cloud@example.test")

    with_env(%{"SELF_HOSTED" => "false"}, fn ->
      SeedGeocodingFromEnv.run(ScratchRepo, env(%{"PHOTON_API_HOST" => "photon.example.test"}))
    end)

    assert settings() == []
  end

  test "skips an environment provider that fails validation" do
    owner = user("invalid@example.test")

    seed(
      env(%{
        "PHOTON_API_HOST" => "app.chibigeo.com",
        "NOMINATIM_API_HOST" => "bad%host",
        "LOCATIONIQ_API_KEY" => " schema-parity-locationiq-key "
      })
    )

    assert settings() == [
             {owner, "locationiq", %{}, ~s({"api_key":"schema-parity-locationiq-key"}), true}
           ]
  end

  test "normalizes a komoot host, forces HTTPS and 1 rps, and drops its key" do
    owner = user("komoot@example.test")

    seed(env(%{"PHOTON_API_HOST" => "HTTPS://Photon.Komoot.IO/", "PHOTON_API_KEY" => "k"}))

    assert settings() == [
             {owner, "photon", %{"host" => "photon.komoot.io", "use_https" => true, "rps" => 1.0},
              nil, true}
           ]
  end

  test "writes a key the way Rails' to_json escapes it" do
    owner = user("escape@example.test")

    seed(env(%{"GEOAPIFY_API_KEY" => "a<b>&c\"d\\e\u2028\u0001\u00E9"}))

    assert [{^owner, "geoapify", %{}, credentials, true}] = settings()
    assert credentials == ~S({"api_key":"a\u003cb\u003e\u0026c\"d\\e\u2028\u0001é"})
  end

  test "skips a provider whose key it cannot encrypt without the encryption keys" do
    owner = user("no-key@example.test")

    seed(
      env(%{
        "OTP_ENCRYPTION_PRIMARY_KEY" => "",
        "PHOTON_API_HOST" => "photon.example.test",
        "PHOTON_API_KEY" => "k",
        "NOMINATIM_API_HOST" => "nominatim.example.test"
      })
    )

    assert settings() == [
             {owner, "nominatim", %{"host" => "nominatim.example.test", "use_https" => true}, nil,
              true}
           ]
  end

  test "an undecryptable winner fails the step with Rails' Decryption, a malformed one with Rails' error" do
    owner = user("undecryptable@example.test")
    setting(owner, "geoapify", %{}, credentials: flipped_tag(~s({"api_key":"k"})))

    assert_raise Ruby.Error, "ActiveRecord::Encryption::Errors::Decryption", fn ->
      seed(env(%{"LOCATIONIQ_API_KEY" => "l"}))
    end

    Dawarich.ScratchRepo.query!("UPDATE service_settings SET credentials = $1", [string_headers()])

    assert_raise Ruby.Error, "undefined method 'each' for an instance of String", fn ->
      seed(env(%{"LOCATIONIQ_API_KEY" => "l"}))
    end
  end

  test "a komoot winner whose key cannot be decrypted fails the step with Rails' Decryption" do
    owner = user("komoot-undecryptable@example.test")
    setting(owner, "photon", %{"host" => "photon.komoot.io"}, credentials: flipped_tag("{}"))

    assert_raise Ruby.Error, "ActiveRecord::Encryption::Errors::Decryption", fn ->
      seed(env(%{"NOMINATIM_API_HOST" => "nominatim.example.test"}))
    end
  end

  test "a later failure reports the Decryption Rails raises while restoring an earlier undecryptable winner" do
    first = user("first@example.test")
    second = user("second@example.test")
    setting(first, "photon", %{"host" => "photon.example.test"}, credentials: flipped_tag("{}"))
    setting(second, "geoapify", %{})

    assert_raise Ruby.Error, "ActiveRecord::Encryption::Errors::Decryption", fn ->
      seed(env(%{"NOMINATIM_API_HOST" => "nominatim.example.test"}))
    end

    Dawarich.ScratchRepo.query!("UPDATE service_settings SET credentials = NULL")

    assert_raise Ruby.Error, "Validation failed: Geoapify needs an API key.", fn ->
      seed(env(%{"NOMINATIM_API_HOST" => "nominatim.example.test"}))
    end
  end

  test "the 20260819120100 step runs the seed" do
    owner = user("step@example.test")

    {_, step, _} =
      V1_13_1.steps()
      |> Enum.map(&Dawarich.ReleaseMigration.normalize/1)
      |> List.keyfind("20260819120100", 0)

    with_env(
      Map.merge(env(%{"PHOTON_API_HOST" => "photon.example.test"}), %{"SELF_HOSTED" => "true"}),
      fn ->
        step.(ScratchRepo)
      end
    )

    assert active_providers() == [{owner, "photon"}]
  end

  defp seed(env) do
    with_env(%{"SELF_HOSTED" => "true"}, fn -> SeedGeocodingFromEnv.run(ScratchRepo, env) end)
  end

  defp active_providers do
    Dawarich.ScratchRepo.query!(
      "SELECT user_id, provider FROM service_settings WHERE active ORDER BY id"
    ).rows
    |> Enum.map(&List.to_tuple/1)
  end
end
