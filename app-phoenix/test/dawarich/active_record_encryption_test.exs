defmodule Dawarich.ActiveRecordEncryptionTest do
  use ExUnit.Case, async: true

  alias Dawarich.{ActiveRecordEncryption, RailsTree}

  @fixture "../fixtures/active_record_encryption.json"
           |> Path.expand(__DIR__)
           |> File.read!()
           |> Jason.decode!()
  @environments @fixture["environments"]

  @explicit Enum.find(@environments, &(&1["name"] == "explicit keys"))
  @development Enum.find(@environments, &(&1["name"] == "development defaults"))

  test "decrypts every ciphertext Rails wrote, with the keys each environment resolves to" do
    for %{"name" => name, "env" => env, "vectors" => vectors} <- @environments do
      assert {:ok, key} = ActiveRecordEncryption.key(env), name

      for vector <- vectors do
        assert ActiveRecordEncryption.decrypt(vector["ciphertext"], key) ==
                 {:ok, plaintext(vector)},
               "#{name}: #{vector["name"]}"
      end
    end
  end

  test "resolves the credentials Rails resolved from the same environment" do
    for %{"name" => name, "env" => env, "credentials" => credentials} <- @environments do
      assert ActiveRecordEncryption.credentials(env) ==
               {:ok,
                %{
                  primary_key: credentials["primary_key"],
                  deterministic_key: credentials["deterministic_key"],
                  key_derivation_salt: credentials["key_derivation_salt"]
                }},
             name
    end
  end

  test "refuses the environments Rails refuses, with Rails' message" do
    refused = for %{"env" => env, "error" => message} <- @environments, do: {env, message}

    assert length(refused) == 2

    for {env, message} <- refused do
      assert ActiveRecordEncryption.key(env) == {:error, message}
    end
  end

  test "Rails still derives its keys the way this module does" do
    source = RailsTree.read("config/application.rb") |> String.replace(~r/\s+/, "")
    {:ok, defaults} = ActiveRecordEncryption.credentials(%{})

    for {var, default} <- [
          {"OTP_ENCRYPTION_PRIMARY_KEY", defaults.primary_key},
          {"OTP_ENCRYPTION_DETERMINISTIC_KEY", defaults.deterministic_key},
          {"OTP_ENCRYPTION_KEY_DERIVATION_SALT", defaults.key_derivation_salt}
        ] do
      assert source =~ "env_or_dev_default('#{var}','#{default}')"
    end

    for line <- [
          "returnENV[var]ifENV[var]",
          "returndev_defaultif!Rails.env.production?||ENV['SECRET_KEY_BASE_DUMMY']",
          "secret=ENV['SECRET_KEY_BASE']",
          "returnderive_encryption_key(var,secret)ifsecret",
          ~S|raise"#{var}requiredinproduction"|,
          ~S|ActiveSupport::KeyGenerator.new(secret,iterations:1000).generate_key("dawarich/encryption/#{var}",32).unpack1('H*')|,
          "config.load_defaults8.1"
        ] do
      assert String.contains?(source, line), line
    end

    settings =
      for path <- RailsTree.wildcard("config/**/*.rb"),
          match <- Regex.scan(~r/active_record\.encryption\.\w+/, RailsTree.read(path)),
          do: {path, hd(match)}

    assert settings == [
             {"config/application.rb", "active_record.encryption.primary_key"},
             {"config/application.rb", "active_record.encryption.deterministic_key"},
             {"config/application.rb", "active_record.encryption.key_derivation_salt"}
           ]
  end

  test "Rails still parses messages and names encodings the way the recorded cases show" do
    assert RailsTree.read("config/initializers/oj.rb") =~ ~r/^Oj\.optimize_rails$/m
    assert String.trim(RailsTree.read(".ruby-version")) == @fixture["ruby"]
  end

  test "no committed dotenv file hands Rails keys the release would not see" do
    files = RailsTree.tracked(".env*")

    assert ".env.development" in files

    for path <- files do
      refute RailsTree.read(path) =~
               ~r/^\s*(export\s+)?(OTP_ENCRYPTION_|SECRET_KEY_BASE)\w*\s*=/m,
             "#{path} sets an encryption key or SECRET_KEY_BASE"
    end
  end

  test "encrypts each plaintext into the message shape Rails wrote for it" do
    key = key!(@explicit)

    for vector <- @explicit["vectors"] do
      ours = ActiveRecordEncryption.encrypt(plaintext(vector), key)

      assert header_names(ours) == header_names(vector["ciphertext"]) -- ["e"], vector["name"]
      assert ActiveRecordEncryption.decrypt(ours, key) == {:ok, plaintext(vector)}
    end
  end

  test "never repeats a ciphertext, with a 12-byte IV and a 16-byte tag" do
    key = key!(@explicit)
    first = ActiveRecordEncryption.encrypt("the same plaintext", key)
    second = ActiveRecordEncryption.encrypt("the same plaintext", key)

    refute first == second

    for ciphertext <- [first, second] do
      assert %{"p" => _, "h" => %{"iv" => iv, "at" => tag}} = Jason.decode!(ciphertext)
      assert byte_size(Base.decode64!(iv)) == 12
      assert byte_size(Base.decode64!(tag)) == 16
      assert ActiveRecordEncryption.decrypt(ciphertext, key) == {:ok, "the same plaintext"}
    end
  end

  test "accepts and refuses each crafted message exactly as Rails did" do
    key = key!(@explicit)
    crafted = @explicit["crafted"]

    assert Enum.any?(crafted, &(&1["rails"] == "ok"))
    assert Enum.any?(crafted, &(&1["rails"] != "ok"))

    for %{"name" => name, "ciphertext" => ciphertext, "rails" => rails} = recorded <- crafted do
      if rails == "ok" do
        assert ActiveRecordEncryption.decrypt(ciphertext, key) == {:ok, recorded["plaintext"]},
               name
      else
        assert {:error, _} = ActiveRecordEncryption.decrypt(ciphertext, key),
               "#{name}: Rails raised #{rails}"
      end
    end
  end

  test "a wrong key or a value that is not a string is an error" do
    [vector | _] = @explicit["vectors"]

    assert {:error, _} = ActiveRecordEncryption.decrypt(vector["ciphertext"], key!(@development))
    assert {:error, _} = ActiveRecordEncryption.decrypt(nil, key!(@explicit))
  end

  test "every truncation of a ciphertext is an error, never an exception" do
    key = key!(@explicit)
    vector = Enum.find(@explicit["vectors"], &(&1["name"] == "long credentials json, compressed"))
    ciphertext = vector["ciphertext"]

    for size <- 0..(byte_size(ciphertext) - 1) do
      assert {:error, _} = ActiveRecordEncryption.decrypt(binary_part(ciphertext, 0, size), key)
    end
  end

  defp key!(environment) do
    {:ok, key} = ActiveRecordEncryption.key(environment["env"])
    key
  end

  defp plaintext(%{"plaintext" => text}), do: text
  defp plaintext(%{"plaintext_base64" => encoded}), do: Base.decode64!(encoded)

  defp header_names(ciphertext) do
    ciphertext |> Jason.decode!() |> Map.fetch!("h") |> Map.keys() |> Enum.sort()
  end
end
