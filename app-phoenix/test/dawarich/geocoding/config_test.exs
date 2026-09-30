defmodule Dawarich.Geocoding.ConfigTest do
  use Dawarich.GeocodingCase, async: false

  alias Dawarich.Geocoding.{Config, Query}

  @chain_cases ~w(env_pin_beats_stored stored_encrypted_key_decrypts undecryptable_secret_absent no_candidate
                  photon_https_forced_komoot photon_https_forced_chibigeo rps_komoot_locked rps_chibigeo_clamped
                  rps_blank rps_zero rps_custom)
  @stored_false_cases ~w(stored_store_geodata_false no_candidate_store_geodata_false nominatim_stored_http)

  test "the provider chain, pins and stored values" do
    for name <- @chain_cases, do: assert_case!(name)

    for host <- ~w(photon.dawarich.app photon.komoot.io app.chibigeo.com/v1/photon) do
      env = %{"PHOTON_API_HOST" => host, "PHOTON_API_USE_HTTPS" => "false"}
      assert %{source: :env, use_https: true} = Config.resolve(ScratchRepo, env)
    end
  end

  test "a stored false wins over a true default" do
    for name <- @stored_false_cases, do: assert_case!(name)

    config = case_config("nominatim_stored_http")
    {url, _key, _headers} = Query.build(config, {51.3397, 12.3731}, [], "0.0.0")
    assert String.starts_with?(url, "http://nominatim.selfhosted.example.test/reverse?")
  end

  defp assert_case!(name) do
    assert {name, comparable(case_config(name))} ==
             {name, fixture_config(find_case(name)["expected"])}
  end

  defp case_config(name) do
    ScratchRepo.query!("TRUNCATE instance_settings", [], log: false)
    c = find_case(name)
    Wave5bFixtures.load_input!(ScratchRepo, c["input"])
    Config.resolve(ScratchRepo, c["env"])
  end

  defp find_case(name),
    do: Enum.find(fixture("config_resolution")["cases"], &(&1["name"] == name))
end
