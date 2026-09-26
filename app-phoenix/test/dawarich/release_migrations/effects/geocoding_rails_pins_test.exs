defmodule Dawarich.ReleaseMigrations.Effects.GeocodingRailsPinsTest do
  use ExUnit.Case, async: true

  alias Dawarich.ActiveRecordEncryption.Message
  alias Dawarich.RailsTree
  alias Dawarich.ReleaseMigrations.Effects.BackfillInstanceSettings

  alias Dawarich.ReleaseMigrations.Effects.Support.{
    GeocodingSchema,
    InstanceSettingsRegistry,
    Ruby,
    RubyFloat,
    ServiceSetting
  }

  @numbers "../../../fixtures/ruby_numbers.json"
           |> Path.expand(__DIR__)
           |> File.read!()
           |> Jason.decode!()
  @floats "../../../fixtures/ruby_floats.json"
          |> Path.expand(__DIR__)
          |> File.read!()
          |> Jason.decode!()
  @oj "../../../fixtures/oj_parse.json" |> Path.expand(__DIR__) |> File.read!() |> Jason.decode!()
  @oj_rejects_but_flagged ["vertical tab whitespace"]

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

  test "formats floats exactly as Ruby's Float#to_s and Oj's Rails encoder did" do
    assert @floats["oj"] == oj_version()

    for [hex, to_s, json] <- @floats["floats"] do
      <<value::float>> = Base.decode16!(hex, case: :lower)
      assert RubyFloat.to_s(value) == to_s, hex
      assert RubyFloat.json(value) == json, hex
    end
  end

  test "never reads as {} a text Oj parses, and reads as {} what Oj rejects" do
    assert @oj["oj"] == oj_version()

    for %{"name" => name, "input_base64" => input, "rails" => rails} <- @oj["cases"] do
      verdict =
        case Message.decode_json(Base.decode64!(input)) do
          {:ok, _term} -> :parsed
          {:error, {:rescued, _reason}} -> :rejected
          {:error, {:unreproducible, _message}} -> :unreproducible
        end

      cond do
        rails == "ok" -> assert verdict in [:parsed, :unreproducible], name
        name in @oj_rejects_but_flagged -> assert verdict == :unreproducible, name
        true -> assert verdict == :rejected, name
      end
    end
  end

  test "keeps \"cannot reproduce Ruby\" apart from errors Ruby raises" do
    assert_raise Ruby.Unreproducible, fn -> Ruby.to_s(%{"a" => 1}) end
    assert Ruby.to_s(1.0e20) == "1.0e+20"
  end

  test "treats blank values the way ActiveSupport's blank? does" do
    for value <- [nil, false, "", " \t", "\u00A0", "\u3000", [], %{}, {:object, []}] do
      assert Ruby.blank?(value), inspect(value)
    end

    for value <- [true, 0, 0.0, "a", [nil], %{"a" => 1}, {:object, [{"a", 1}]}] do
      refute Ruby.blank?(value), inspect(value)
    end
  end

  defp oj_version do
    [_, version] = Regex.run(~r/^    oj \((\S+)\)$/m, RailsTree.read("Gemfile.lock"))
    version
  end

  defp ruby(:infinity), do: "Infinity"
  defp ruby(:neg_infinity), do: "-Infinity"
  defp ruby(value), do: value
end
