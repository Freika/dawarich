defmodule Dawarich.ActiveRecordEncryption do
  @moduledoc false

  alias Dawarich.ActiveRecordEncryption.{Message, Zlib}

  @variables [
    primary_key: "OTP_ENCRYPTION_PRIMARY_KEY",
    deterministic_key: "OTP_ENCRYPTION_DETERMINISTIC_KEY",
    key_derivation_salt: "OTP_ENCRYPTION_KEY_DERIVATION_SALT"
  ]
  @dev_defaults %{
    "OTP_ENCRYPTION_PRIMARY_KEY" => "dawarich-dev-primary-key-not-for-production",
    "OTP_ENCRYPTION_DETERMINISTIC_KEY" => "dawarich-dev-deterministic-not-for-prod",
    "OTP_ENCRYPTION_KEY_DERIVATION_SALT" => "dawarich-dev-salt-not-for-production"
  }
  @compression_threshold 140
  @external_resource encodings = Path.expand("../../priv/ruby_encodings.txt", __DIR__)
  @ruby_encodings encodings
                  |> File.read!()
                  |> String.split("\n", trim: true)
                  |> MapSet.new(&String.upcase(&1, :ascii))

  def credentials(env \\ System.get_env()) do
    Enum.reduce_while(@variables, {:ok, %{}}, fn {name, var}, {:ok, resolved} ->
      case setting(env, var) do
        {:ok, value} -> {:cont, {:ok, Map.put(resolved, name, value)}}
        error -> {:halt, error}
      end
    end)
  end

  def key(env \\ System.get_env()) do
    with {:ok, %{primary_key: primary, key_derivation_salt: salt}} <- credentials(env),
         :ok <- present(primary, "primary_key"),
         :ok <- present(salt, "key_derivation_salt") do
      {:ok, :crypto.pbkdf2_hmac(:sha256, primary, salt, 65_536, 32)}
    end
  end

  def encrypt(plaintext, key) when is_binary(plaintext) and byte_size(key) == 32 do
    {payload, compressed} = compress(plaintext)
    iv = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, payload, "", true)

    headers =
      [iv: Base.encode64(iv), at: Base.encode64(tag)] ++ if(compressed, do: [c: true], else: [])

    Jason.encode!(
      Jason.OrderedObject.new(p: Base.encode64(ciphertext), h: Jason.OrderedObject.new(headers))
    )
  end

  def decrypt(ciphertext, key) when is_binary(ciphertext) and byte_size(key) == 32 do
    with {:ok, {:message, payload, headers}} <- Message.parse(ciphertext),
         :ok <- key_reference(headers["i"], key),
         {:ok, tag} <- auth_tag(headers["at"]),
         {:ok, iv} <- iv(headers["iv"]),
         {:ok, payload} <- payload(payload),
         {:ok, clear} <- open(key, iv, payload, tag),
         :ok <- encoding(headers["e"]) do
      uncompress(clear, headers["c"])
    end
  end

  def decrypt(_ciphertext, _key), do: Message.rescued(:invalid_message)

  defp setting(env, var) do
    cond do
      Map.has_key?(env, var) ->
        {:ok, env[var]}

      not production?(env) or Map.has_key?(env, "SECRET_KEY_BASE_DUMMY") ->
        {:ok, @dev_defaults[var]}

      secret = env["SECRET_KEY_BASE"] ->
        {:ok, derive(secret, var)}

      true ->
        {:error, "#{var} required in production"}
    end
  end

  defp production?(env) do
    Enum.find_value(["RAILS_ENV", "RACK_ENV"], "development", fn var ->
      if present?(env[var]), do: env[var]
    end) == "production"
  end

  defp derive(secret, var) do
    :sha
    |> :crypto.pbkdf2_hmac(secret, "dawarich/encryption/" <> var, 1000, 32)
    |> Base.encode16(case: :lower)
  end

  defp present(value, name) do
    if present?(value),
      do: :ok,
      else:
        {:error, "Missing Active Record encryption credential: active_record_encryption.#{name}"}
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp compress(text) when byte_size(text) > @compression_threshold,
    do: {:zlib.compress(text), true}

  defp compress(text), do: {text, false}

  defp key_reference(id, _key) when id in [nil, false], do: :ok

  defp key_reference(id, key) do
    if id == :sha |> :crypto.hash(key) |> Base.encode16(case: :lower) |> binary_part(0, 4),
      do: :ok,
      else: Message.rescued(:unknown_key)
  end

  defp auth_tag(nil), do: Message.rescued(:missing_tag)
  defp auth_tag(<<_::binary-size(16)>> = tag), do: {:ok, tag}
  defp auth_tag(tag) when is_binary(tag), do: Message.rescued(:invalid_tag)
  defp auth_tag(tag) when is_number(tag), do: no_method("length", tag)
  defp auth_tag(tag), do: no_method("bytes", tag)

  defp iv(<<_::binary-size(12)>> = iv), do: {:ok, iv}
  defp iv(_iv), do: Message.rescued(:invalid_iv)

  defp payload(nil), do: no_method("empty?", nil)
  defp payload(payload), do: {:ok, payload}

  defp open(key, iv, payload, tag) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, payload, "", tag, false) do
      clear when is_binary(clear) -> {:ok, clear}
      :error -> Message.rescued(:authentication_failed)
    end
  end

  defp encoding(name) when name in [nil, false], do: :ok

  defp encoding(name) when is_binary(name) do
    cond do
      String.contains?(name, <<0>>) ->
        Message.raised("ArgumentError", "invalid encoding name (NUL byte)")

      MapSet.member?(@ruby_encodings, String.upcase(name, :ascii)) ->
        :ok

      true ->
        Message.raised("ArgumentError", "unknown encoding name - " <> name)
    end
  end

  defp encoding(name),
    do:
      Message.raised(
        "TypeError",
        "no implicit conversion of #{Message.conversion(name)} into String"
      )

  defp no_method(name, value),
    do:
      Message.raised("NoMethodError", "undefined method '#{name}' for #{Message.instance(value)}")

  defp uncompress(clear, compressed) when compressed in [nil, false], do: {:ok, clear}
  defp uncompress(clear, _compressed), do: Zlib.inflate(clear)
end
