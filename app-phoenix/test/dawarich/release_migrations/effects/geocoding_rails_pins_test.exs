defmodule Dawarich.ReleaseMigrations.Effects.GeocodingRailsPinsTest do
  use ExUnit.Case, async: true

  alias Dawarich.RailsTree
  alias Dawarich.ReleaseMigrations.Effects.BackfillInstanceSettings

  alias Dawarich.ReleaseMigrations.Effects.Support.{
    GeocodingSchema,
    InstanceSettingsRegistry,
    Ruby,
    ServiceSetting
  }

  @numbers "../../../fixtures/ruby_numbers.json"
           |> Path.expand(__DIR__)
           |> File.read!()
           |> Jason.decode!()

  test "the registry equals InstanceSettings::Registry, in order, with kinds and defaults" do
    source = RailsTree.read("app/services/instance_settings/registry.rb")

    definitions =
      ~r/Definition\.new\(key: :(\w+), env_var: '(\w+)', kind: :(\w+),?\s*(?:default: (\w+))?\)/
      |> Regex.scan(source, capture: :all_but_first)
      |> Enum.map(fn [key, var, kind | default] ->
        {key, var, String.to_atom(kind),
         default |> List.first("nil") |> Code.eval_string() |> elem(0)}
      end)

    assert length(Regex.scan(~r/\bDefinition\.new\b/, source)) == length(definitions)
    assert InstanceSettingsRegistry.definitions() == definitions
  end

  test "the provider chain, names, hosts and host format equal Rails'" do
    providers = RailsTree.read("app/services/geocoding/providers.rb")
    constants = RailsTree.read("config/initializers/01_constants.rb")
    schema = RailsTree.read("app/models/service_settings/geocoding_schema.rb")

    assert providers =~ "CHAIN = %w[#{Enum.join(ServiceSetting.chain(), " ")}].freeze"
    assert providers =~ "HOST_REQUIRED = %w[photon nominatim].freeze"
    assert providers =~ "API_KEY_REQUIRED = %w[geoapify locationiq].freeze"
    assert providers =~ "KOMOOT_HOST = 'photon.komoot.io'"
    assert providers =~ "CHIBIGEO_BARE_HOST = 'app.chibigeo.com'"

    assert providers =~
             "'photon' => 'Photon', 'geoapify' => 'Geoapify',\n      'nominatim' => 'Nominatim', 'locationiq' => 'LocationIQ'"

    assert constants =~
             "PHOTON_HTTPS_ONLY_HOSTS = %w[#{Enum.join(GeocodingSchema.https_only_hosts(), " ")}].freeze"

    assert constants =~
             "NOMINATIM_API_USE_HTTPS = ENV.fetch('NOMINATIM_API_USE_HTTPS', 'true') == 'true'"

    assert schema =~ ~S"HOST_FORMAT = %r{\A[a-z0-9_][a-z0-9._-]*(:\d+)?(/[a-z0-9._/-]*)?\z}"
  end

  test "validation messages equal config/locales/en.yml" do
    [_, block] =
      String.split(RailsTree.read("config/locales/en.yml"), "\n        service_setting:\n",
        parts: 2
      )

    for {key, message} <- GeocodingSchema.messages() do
      assert block =~ ~r/^\s+#{key}: ["']#{Regex.escape(message)}["']$/m, "#{key}"
    end
  end

  test "rate limits equal Geocoding::RateLimits" do
    source = RailsTree.read("app/services/geocoding/rate_limits.rb")

    for line <- [
          "KOMOOT_RPS = 1.0",
          "CHIBIGEO_DEFAULT_RPS = 1.0",
          "CHIBIGEO_MIN_RPS = 1.0",
          "CHIBIGEO_MAX_RPS = 25.0",
          "CUSTOM_MIN = 0.1",
          "CUSTOM_MAX = 1000.0"
        ] do
      assert source =~ line
    end
  end

  test "the backfill's key maps equal InstanceSettings::Backfill and Geocoding::Config" do
    backfill = RailsTree.read("app/services/instance_settings/backfill.rb")
    config = RailsTree.read("app/services/geocoding/config.rb")

    assert backfill =~
             "KEY_FOR_HOST = { 'photon' => :photon_api_host, 'nominatim' => :nominatim_api_host }.freeze"

    assert backfill =~ "'photon' => :photon_api_key, 'nominatim' => :nominatim_api_key,"
    assert backfill =~ "'geoapify' => :geoapify_api_key, 'locationiq' => :locationiq_api_key"

    assert config =~
             "PROVIDER_KEYS = { photon: :photon_api_host, geoapify: :geoapify_api_key,\n                      nominatim: :nominatim_api_host, locationiq: :locationiq_api_key }.freeze"

    assert BackfillInstanceSettings.provider_keys() ==
             ~w[photon_api_host geoapify_api_key nominatim_api_host locationiq_api_key]
  end

  test "reads numbers exactly as Ruby's Float() and String#to_f did" do
    assert String.trim(RailsTree.read(".ruby-version")) == @numbers["ruby"]

    for [string, float, to_f] <- @numbers["cases"] do
      assert ruby(Ruby.float(string)) == float, "Float(#{inspect(string)})"
      assert ruby(Ruby.to_f(string)) == to_f, "#{inspect(string)}.to_f"
    end
  end

  test "treats blank values the way ActiveSupport's blank? does" do
    for value <- [nil, false, "", " \t", "\u00A0", "\u3000", [], %{}, {:object, []}] do
      assert Ruby.blank?(value), inspect(value)
    end

    for value <- [true, 0, 0.0, "a", [nil], %{"a" => 1}, {:object, [{"a", 1}]}] do
      refute Ruby.blank?(value), inspect(value)
    end
  end

  defp ruby(:infinity), do: "Infinity"
  defp ruby(:neg_infinity), do: "-Infinity"
  defp ruby(value), do: value
end
