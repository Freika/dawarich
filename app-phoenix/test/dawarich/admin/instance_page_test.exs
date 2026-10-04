defmodule Dawarich.Admin.InstancePageTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.ActiveRecordEncryption
  alias Dawarich.Admin.InstancePage

  setup do
    ScratchRepo.query!("TRUNCATE instance_settings, service_settings", [], log: false)
    :ok
  end

  test "instance fields honor env stored and default precedence without retaining secrets" do
    env = %{"PHOTON_API_HOST" => "  ", "LOCATIONIQ_API_KEY" => "synthetic-env-secret"}
    secret!("geoapify_api_key", "synthetic-stored-secret")
    setting!("photon_api_host", "stored.example.invalid")
    setting!("store_geodata", false)
    setting!("nominatim_api_host", nil)
    assert {:ok, data} = InstancePage.load(ScratchRepo, env)
    assert data.geocoding.provider == :locationiq
    assert data.section_default == "locationiq"
    assert data.fields["photon_api_host"].source == :stored
    assert data.fields["store_geodata"].value == false
    assert data.fields["store_geodata"].source == :stored
    assert data.fields["nominatim_api_host"].source == :default
    assert data.fields["locationiq_api_key"].pinned
    assert data.fields["locationiq_api_key"].present
    assert data.fields["geoapify_api_key"].present
    assert data.fields["geoapify_api_key"].value == nil
    refute inspect(data) =~ "synthetic-env-secret"
    refute inspect(data) =~ "synthetic-stored-secret"
    refute Map.has_key?(data.geocoding, :api_key)

    assert {:ok, host_pin} =
             InstancePage.load(ScratchRepo, %{"PHOTON_API_HOST" => "pinned.example.invalid"})

    assert host_pin.fields["photon_api_host"].value == "pinned.example.invalid"
    assert {:ok, pinned} = InstancePage.load(ScratchRepo, %{"STORE_GEODATA" => "false"})
    assert pinned.fields["store_geodata"].pinned
    assert pinned.fields["store_geodata"].value == false
    assert {:ok, invalid} = InstancePage.load(ScratchRepo, %{"REVERSE_GEOCODING_RPS" => "bogus"})
    assert invalid.fields["reverse_geocoding_rps"].source == :env
    assert invalid.fields["reverse_geocoding_rps"].value == nil
  end

  test "unreadable secret indicators outrank section state" do
    ScratchRepo.query!(
      "INSERT INTO instance_settings(key, encrypted_value, created_at, updated_at) VALUES('geoapify_api_key', 'corrupt-synthetic', now(), now())",
      [],
      log: false
    )

    assert {:ok, data} = InstancePage.load(ScratchRepo, %{"GEOAPIFY_API_KEY" => "synthetic-pin"})
    field = data.fields["geoapify_api_key"]
    assert field.unreadable
    assert field.pinned
    assert field.value == nil
    refute field.clear
    assert InstancePage.section_status(data, "geoapify") == :attention
    assert {:ok, unpinned} = InstancePage.load(ScratchRepo, %{})
    field = unpinned.fields["geoapify_api_key"]
    assert field.unreadable
    assert field.clear
    refute field.present
    assert field.source == :default
    secret!("nominatim_api_key", "synthetic-readable")
    assert {:ok, readable} = InstancePage.load(ScratchRepo, %{})
    assert readable.fields["nominatim_api_key"].clear
    refute readable.fields["nominatim_api_key"].unreadable
  end

  test "TLS and section fallback match Rails" do
    setting!("reverse_geocoding_rps", 5.0)

    for host <- ~w(photon.dawarich.app photon.komoot.io:443/path app.chibigeo.com/v1/photon) do
      env = %{"PHOTON_API_HOST" => host, "PHOTON_API_USE_HTTPS" => "false"}
      assert {:ok, data} = InstancePage.load(ScratchRepo, env)
      assert data.geocoding.use_https
      field = data.fields["photon_api_use_https"]
      assert field.locked_on
      assert field.disabled
      refute field.hidden_false
      assert data.fields["reverse_geocoding_rps"].display == 5
      assert InstancePage.section(data, "unknown") == "photon"
      assert InstancePage.section(data, "") == "photon"
      assert InstancePage.section(data, "points") == "points"
    end

    assert {:ok, data} = InstancePage.load(ScratchRepo, %{})
    assert data.section_default == "photon"
    assert data.fields["photon_api_use_https"].hidden_false
    secret!("geoapify_api_key", "synthetic-readable")
    assert {:ok, data} = InstancePage.load(ScratchRepo, %{})
    assert InstancePage.section(data, nil) == "geoapify"
  end

  defp setting!(name, value) do
    ScratchRepo.query!(
      "INSERT INTO instance_settings(key, value, created_at, updated_at) VALUES($1, $2, now(), now())",
      [name, value],
      log: false
    )
  end

  defp secret!(name, value) do
    {:ok, key} = ActiveRecordEncryption.key(%{})
    encrypted = ActiveRecordEncryption.encrypt(value, key)

    ScratchRepo.query!(
      "INSERT INTO instance_settings(key, encrypted_value, created_at, updated_at) VALUES($1, $2, now(), now())",
      [name, encrypted],
      log: false
    )
  end
end
