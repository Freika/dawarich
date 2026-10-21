defmodule Dawarich.Imports.RailsBlobReference do
  @moduledoc false
  def verify(token) when is_binary(token) do
    with [data, signature] <- String.split(token, "--"),
         true <- byte_size(signature) == 40,
         secret when is_binary(secret) <- Dawarich.RailsSecret.fetch(),
         key <-
           Plug.Crypto.KeyGenerator.generate(secret, "ActiveStorage",
             iterations: 1000,
             length: 64,
             digest: :sha256
           ),
         expected <- Base.encode16(:crypto.mac(:hmac, :sha, key, data), case: :lower),
         true <- Plug.Crypto.secure_compare(expected, signature),
         {:ok, bytes} <- Base.decode64(data),
         true <- Base.encode64(bytes) == data,
         {:ok, %{"_rails" => %{"data" => id, "pur" => "blob_id"} = metadata}} <-
           Jason.decode(bytes),
         true <- is_integer(id) and id > 0,
         true <- valid_expiry?(metadata["exp"]) do
      {:ok, id}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def verify(_), do: {:error, :invalid_token}
  defp valid_expiry?(nil), do: true

  defp valid_expiry?(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, time, _} -> DateTime.compare(time, DateTime.utc_now()) == :gt
      _ -> false
    end
  end

  defp valid_expiry?(_), do: false
end
