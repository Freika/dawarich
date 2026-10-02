defmodule Dawarich.RailsMessages do
  @moduledoc false

  alias Dawarich.RailsSecret
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @storage "ActiveStorage"
  @turbo "turbo/signed_stream_verifier_key"

  def blob_id(id, secret \\ RailsSecret.fetch()),
    do: sign(@storage, ~s({"_rails":{"data":#{id},"pur":"blob_id"}}), :sha, secret)

  def stream_name(parts, secret \\ RailsSecret.fetch()) do
    name = Enum.map_join(parts, ":", &part/1)
    sign(@turbo, Jason.encode!(name, escape: :javascript_safe), :sha256, secret)
  end

  def verified_stream_name(signed, secret \\ RailsSecret.fetch()) do
    case open(signed, @turbo, :sha256, secret, nil, DateTime.utc_now()) do
      {:ok, name} when is_binary(name) -> {:ok, name}
      _ -> :error
    end
  end

  def sign_storage(data, purpose, %DateTime{} = expires_at, secret \\ RailsSecret.fetch()) do
    meta = Jason.OrderedObject.new(data: data, exp: iso8601_ms(expires_at), pur: purpose)
    sign(@storage, json(%{"_rails" => meta}), :sha, secret)
  end

  def verify_storage(signed, purpose, %DateTime{} = now, secret \\ RailsSecret.fetch()),
    do: open(signed, @storage, :sha, secret, purpose, now)

  def verified_blob_id(signed, %DateTime{} = now, secret \\ RailsSecret.fetch()) do
    case verify_storage(signed, "blob_id", now, secret) do
      {:ok, id} when is_integer(id) and id > 0 -> {:ok, id}
      _ -> :error
    end
  end

  def json(term), do: term |> Jason.encode!() |> Ruby.json_text()

  def iso8601_ms(%DateTime{time_zone: "Etc/UTC", microsecond: {us, _}} = at),
    do: DateTime.to_iso8601(%{at | microsecond: {div(us, 1000) * 1000, 3}})

  def key(secret, salt, iterations, length) do
    id = {__MODULE__, :crypto.hash(:sha256, secret), salt, iterations, length}

    case :persistent_term.get(id, nil) do
      nil ->
        key = :crypto.pbkdf2_hmac(:sha256, secret, salt, iterations, length)
        :persistent_term.put(id, key)
        key

      key ->
        key
    end
  end

  defp part({model, id}) when is_atom(model),
    do:
      Base.url_encode64("gid://dawarich/#{Macro.camelize(Atom.to_string(model))}/#{id}",
        padding: false
      )

  defp part(value), do: to_string(value)

  defp sign(salt, json, digest, secret) do
    data = Base.encode64(json)
    data <> "--" <> mac(digest, key(secret, salt, 1000, 64), data)
  end

  defp mac(digest, key, data),
    do: :hmac |> :crypto.mac(digest, key, data) |> Base.encode16(case: :lower)

  defp open(signed, salt, digest, secret, purpose, now)
       when is_binary(signed) and is_binary(secret) do
    hex = if digest == :sha, do: 40, else: 64
    size = byte_size(signed) - hex - 2

    with true <- size > 0 and String.valid?(signed),
         <<data::binary-size(size), "--", signature::binary-size(hex)>> <- signed,
         true <-
           Plug.Crypto.secure_compare(signature, mac(digest, key(secret, salt, 1000, 64), data)),
         {:ok, json} <- Base.decode64(data),
         {:ok, value} <- Jason.decode(json) do
      unwrap(json, value, purpose, now)
    else
      _ -> :error
    end
  end

  defp open(_signed, _salt, _digest, _secret, _purpose, _now), do: :error

  defp unwrap(json, %{"_rails" => %{} = meta}, purpose, now) do
    cond do
      expired?(meta["exp"], now) -> :error
      not same_purpose?(meta["pur"], purpose) -> :error
      String.starts_with?(json, ~s({"_rails":{"message":)) -> legacy(meta["message"])
      true -> {:ok, meta["data"]}
    end
  end

  defp unwrap(_json, value, nil, _now), do: {:ok, value}
  defp unwrap(_json, _value, _purpose, _now), do: :error

  defp expired?(nil, _now), do: false

  defp expired?(exp, now) when is_binary(exp) do
    case DateTime.from_iso8601(exp) do
      {:ok, at, _offset} -> DateTime.compare(now, at) != :lt
      _ -> true
    end
  end

  defp expired?(_exp, _now), do: true

  defp same_purpose?(pur, purpose) when is_binary(pur) or is_nil(pur),
    do: to_string(pur) == to_string(purpose)

  defp same_purpose?(pur, purpose) when is_integer(pur),
    do: Integer.to_string(pur) == to_string(purpose)

  defp same_purpose?(_pur, _purpose), do: false

  defp legacy(message) when is_binary(message) do
    with {:ok, inner} <- Base.decode64(message),
         {:ok, value} <- Jason.decode(inner) do
      {:ok, value}
    else
      _ -> :error
    end
  end

  defp legacy(_message), do: :error
end
