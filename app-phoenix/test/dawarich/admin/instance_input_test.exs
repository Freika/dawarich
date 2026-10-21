defmodule Dawarich.Admin.InstanceInputTest do
  use ExUnit.Case, async: true
  alias Dawarich.Admin.InstanceInput
  alias Dawarich.I18n
  alias Dawarich.ReleaseMigrations.Effects.Support.InstanceSettingsRegistry, as: Registry

  test "matches registered coercion blank-secret clear and host validation" do
    assert Code.ensure_loaded?(InstanceInput), "instance input must exist"
    definitions = Registry.definitions()
    input = for {key, _, _, _} <- definitions, do: {key, " "}
    assert {:ok, values} = InstanceInput.prepare(params(input), %{}, %{}, "en")

    assert values ==
             for({key, _, kind, default} <- definitions, kind != :secret, do: {key, default})

    assert {:ok, []} =
             InstanceInput.prepare(
               params([{"geoapify_api_key", " "}, {"unknown", "x"}]),
               %{},
               %{},
               "en"
             )

    for clear <- ["1", "0", "false"] do
      assert {:ok, [{"geoapify_api_key", nil}]} =
               InstanceInput.prepare(
                 Map.put(params([{"geoapify_api_key", " "}]), "instance_settings_clear", %{
                   "geoapify_api_key" => clear
                 }),
                 %{},
                 %{},
                 "en"
               )
    end

    assert {:ok, [{"geoapify_api_key", "synthetic-input"}]} =
             InstanceInput.prepare(
               params([{"geoapify_api_key", " synthetic-input "}]),
               %{},
               %{},
               "en"
             )

    assert {:ok,
            [
              {"photon_api_host", "example.invalid:123/path"},
              {"store_geodata", true},
              {"reverse_geocoding_rps", 2.5}
            ]} =
             InstanceInput.prepare(
               params([
                 {"photon_api_host", " HTTPS://EXAMPLE.INVALID:123/path/// "},
                 {"store_geodata", " true "},
                 {"reverse_geocoding_rps", "2.5"}
               ]),
               %{},
               %{},
               "en"
             )

    for locale <- ["en", "de"] do
      {:ok, host_error} = I18n.t(locale, "admin.settings.update.host_invalid")
      {:ok, key_error} = I18n.t(locale, "admin.settings.update.chibigeo_key_required")

      assert {:invalid, ^host_error} =
               InstanceInput.prepare(
                 params([{"nominatim_api_host", "bad host"}]),
                 %{},
                 %{},
                 locale
               )

      assert {:invalid, ^key_error} =
               InstanceInput.prepare(
                 params([{"photon_api_host", "app.chibigeo.com"}]),
                 %{},
                 %{},
                 locale
               )

      assert {:invalid, message} =
               InstanceInput.prepare(
                 params([
                   {"nominatim_api_host", "bad host"},
                   {"photon_api_host", "app.chibigeo.com"}
                 ]),
                 %{},
                 %{},
                 locale
               )

      assert message == host_error <> " " <> key_error

      assert {:ok, [{"photon_api_host", "app.chibigeo.com"}]} =
               InstanceInput.prepare(
                 params([{"photon_api_host", "app.chibigeo.com"}]),
                 %{"photon_api_key" => "synthetic-stored"},
                 %{},
                 locale
               )
    end
  end

  test "drops Komoot key only when source input permits it" do
    assert Code.ensure_loaded?(InstanceInput), "instance input must exist"

    input =
      params([
        {"photon_api_key", "synthetic-input"},
        {"photon_api_host", "https://photon.komoot.io/"}
      ])

    assert {:ok, [{"photon_api_key", nil}, {"photon_api_host", "photon.komoot.io"}]} =
             InstanceInput.prepare(input, %{}, %{}, "en")

    pinned = %{"PHOTON_API_KEY" => "synthetic-pin"}

    assert {:ok, [{"photon_api_key", "synthetic-input"}, {"photon_api_host", "photon.komoot.io"}]} =
             InstanceInput.prepare(input, %{}, pinned, "en")

    assert {:ok, [{"photon_api_host", "photon.komoot.io"}, {"photon_api_key", nil}]} =
             InstanceInput.prepare(
               params([{"photon_api_host", "photon.komoot.io"}]),
               %{},
               %{},
               "en"
             )

    assert {:ok, [{"photon_api_key", "synthetic-input"}]} =
             InstanceInput.prepare(
               params([{"photon_api_key", "synthetic-input"}]),
               %{"photon_api_host" => "photon.komoot.io"},
               %{},
               "en"
             )

    assert {:ok, [{"photon_api_host", "photon.komoot.io"}, {"photon_api_key", nil}]} =
             InstanceInput.prepare(
               params([{"photon_api_host", "photon.komoot.io"}]),
               %{},
               %{"PHOTON_API_HOST" => "app.chibigeo.com"},
               "en"
             )

    assert {:ok, [{"photon_api_key", "synthetic-input"}]} =
             InstanceInput.prepare(
               params([{"photon_api_key", "synthetic-input"}]),
               %{},
               %{"PHOTON_API_HOST" => "app.chibigeo.com"},
               "en"
             )

    assert {:invalid, _} =
             InstanceInput.prepare(
               params([{"photon_api_key", ""}, {"photon_api_host", "app.chibigeo.com"}])
               |> Map.put("instance_settings_clear", %{"photon_api_key" => "1"}),
               %{"photon_api_key" => "synthetic-stored"},
               %{},
               "de"
             )
  end

  defp params(values), do: %{"instance_settings" => values}
end
