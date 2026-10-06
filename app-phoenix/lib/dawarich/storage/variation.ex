defmodule Dawarich.Storage.Variation do
  @moduledoc false
  alias Dawarich.{RailsMessages, RailsSecret}
  alias Dawarich.RailsCache.{Marshal, Value}
  defstruct [:transformations, :pairs, :key]

  def decode(signed, now \\ DateTime.utc_now()) do
    with {:ok, transforms} <- RailsMessages.verify_storage(signed, "variation", now) do
      build(transforms, signed)
    else
      _ -> legacy(signed, now)
    end
  end

  defp build(%{} = transforms, signed) do
    {:ok, %__MODULE__{transformations: transforms, pairs: ordered(signed, transforms), key: signed}}
  end
  defp build(_, _), do: :error

  defp ordered(signed, transforms) do
    with [data, _] <- String.split(signed, "--"),
         {:ok, bytes} <- Base.decode64(data),
         {:ok, value} <- Jason.decode(bytes, objects: :ordered_objects),
         %Jason.OrderedObject{values: pairs} <- value["_rails"]["data"] do
      pairs
    else
      _ -> Enum.to_list(transforms)
    end
  end

  defp legacy(signed, now) when is_binary(signed) do
    with [data, signature] <- String.split(signed, "--"),
         expected = mac(data),
         true <- byte_size(signature) == byte_size(expected) and Plug.Crypto.secure_compare(signature, expected),
         {:ok, bytes} <- Base.decode64(data),
         {:ok, envelope} <- Jason.decode(bytes),
         %{"_rails" => meta} <- envelope,
         true <- meta["pur"] == "variation",
         true <- live?(meta["exp"], now),
         {:ok, inner} <- Base.decode64(meta["message"]),
         {:ok, value} <- Marshal.decode(inner),
         %{} = transforms <- normalize(value) do
      {:ok, %__MODULE__{transformations: transforms, pairs: Enum.to_list(transforms), key: signed}}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end
  defp legacy(_, _), do: :error

  defp normalize(%Value{}), do: :error
  defp normalize({:ruby_symbol, name}), do: name
  defp normalize(value) when is_map(value), do: Map.new(value, fn {k,v} -> {normalize(k), normalize(v)} end)
  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value), do: value

  defp live?(nil, _now), do: true
  defp live?(exp, now) do
    case DateTime.from_iso8601(exp) do
      {:ok, at, _} -> DateTime.compare(now, at) == :lt
      _ -> false
    end
  end

  def sign(pairs) do
    data = RailsMessages.json(%{"_rails" => Jason.OrderedObject.new(data: Jason.OrderedObject.new(pairs), pur: "variation")}) |> Base.encode64()
    data <> "--" <> mac(data)
  end

  defp mac(data), do: :crypto.mac(:hmac, :sha, RailsMessages.key(RailsSecret.fetch(), "ActiveStorage", 1000, 64), data) |> Base.encode16(case: :lower)
end
