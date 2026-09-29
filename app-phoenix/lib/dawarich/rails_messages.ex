defmodule Dawarich.RailsMessages do
  @moduledoc false

  def blob_id(id, secret \\ Dawarich.RailsSecret.fetch()),
    do: sign("ActiveStorage", ~s({"_rails":{"data":#{id},"pur":"blob_id"}}), :sha, secret)

  defp sign(salt, json, digest, secret) do
    data = Base.encode64(json)

    data <>
      "--" <> Base.encode16(:crypto.mac(:hmac, digest, key(salt, secret), data), case: :lower)
  end

  defp key(salt, secret) do
    id = {__MODULE__, :crypto.hash(:sha256, secret), salt}

    case :persistent_term.get(id, nil) do
      nil ->
        key =
          Plug.Crypto.KeyGenerator.generate(secret, salt,
            iterations: 1000,
            length: 64,
            digest: :sha256
          )

        :persistent_term.put(id, key)
        key

      key ->
        key
    end
  end
end
