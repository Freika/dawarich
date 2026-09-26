defmodule Dawarich.ActiveRecordEncryption do
  @moduledoc false

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
  @max_nesting 100
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
    with {:ok, data} <- json(ciphertext),
         {:ok, payload, headers} <- message(data, 1),
         :ok <- key_reference(headers["i"], key),
         {:ok, iv, tag} <- iv_and_tag(headers),
         :ok <- encoding(headers["e"]),
         {:ok, clear} <- open(key, iv, payload, tag) do
      uncompress(clear, headers["c"])
    end
  end

  def decrypt(_ciphertext, _key), do: {:error, :invalid_message}

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

  defp json(ciphertext) do
    with {:ok, data} <- Jason.decode(ciphertext, objects: :ordered_objects),
         {:ok, data} <- unordered(data, 1) do
      {:ok, data}
    else
      _ -> {:error, :invalid_json}
    end
  end

  defp unordered(value, depth)
       when (is_list(value) or is_struct(value, Jason.OrderedObject)) and depth > @max_nesting,
       do: :error

  defp unordered(%Jason.OrderedObject{values: pairs}, depth) do
    {keys, values} = Enum.unzip(pairs)

    with {:ok, values} <- unordered_all(values, depth + 1),
         do: {:ok, Map.new(Enum.zip(keys, values))}
  end

  defp unordered(list, depth) when is_list(list), do: unordered_all(list, depth + 1)
  defp unordered(value, _depth), do: {:ok, value}

  defp unordered_all(items, depth) do
    items
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, done} ->
      case unordered(item, depth) do
        {:ok, item} -> {:cont, {:ok, [item | done]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp message(%{"p" => payload} = data, level) when level <= 2 do
    with {:ok, payload} <- payload(payload),
         {:ok, headers} <- headers(Map.get(data, "h"), level) do
      {:ok, payload, headers}
    end
  end

  defp message(_data, _level), do: {:error, :invalid_message}

  defp payload(value) when is_binary(value), do: base64(value)
  defp payload(_value), do: {:error, :invalid_message}

  defp headers(nil, _level), do: {:ok, %{}}

  defp headers(headers, level) when is_map(headers) do
    Enum.reduce_while(headers, {:ok, %{}}, fn {name, value}, {:ok, decoded} ->
      case header(value, level) do
        {:ok, value} -> {:cont, {:ok, Map.put(decoded, name, value)}}
        error -> {:halt, error}
      end
    end)
  end

  defp headers(_headers, _level), do: {:error, :invalid_message}

  defp header(value, level) when is_map(value) do
    with {:ok, payload, headers} <- message(value, level + 1), do: {:ok, {payload, headers}}
  end

  defp header(value, _level) when is_binary(value), do: base64(value)
  defp header(value, _level) when is_list(value), do: {:error, :invalid_message}
  defp header(value, _level), do: {:ok, value}

  defp base64(value) do
    with {:ok, decoded} <- Base.decode64(value),
         ^value <- Base.encode64(decoded) do
      {:ok, decoded}
    else
      _ -> {:error, :invalid_base64}
    end
  end

  defp key_reference(id, _key) when id in [nil, false], do: :ok

  defp key_reference(id, key) do
    if id == :sha |> :crypto.hash(key) |> Base.encode16(case: :lower) |> binary_part(0, 4),
      do: :ok,
      else: {:error, :unknown_key}
  end

  defp encoding(name) when name in [nil, false], do: :ok

  defp encoding(name) when is_binary(name) do
    if MapSet.member?(@ruby_encodings, String.upcase(name, :ascii)),
      do: :ok,
      else: {:error, :unknown_encoding}
  end

  defp encoding(_name), do: {:error, :unknown_encoding}

  defp iv_and_tag(%{"iv" => <<_::binary-size(12)>> = iv, "at" => <<_::binary-size(16)>> = tag}),
    do: {:ok, iv, tag}

  defp iv_and_tag(_headers), do: {:error, :invalid_message}

  defp open(key, iv, payload, tag) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, payload, "", tag, false) do
      clear when is_binary(clear) -> {:ok, clear}
      :error -> {:error, :authentication_failed}
    end
  end

  defp uncompress(clear, compressed) when compressed in [nil, false], do: {:ok, clear}

  defp uncompress(clear, _compressed) do
    {:ok, :zlib.uncompress(clear)}
  rescue
    ErlangError -> {:error, :invalid_compression}
  end
end
