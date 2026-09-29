defmodule Dawarich.RailsMessages do
  @moduledoc false

  def blob_id(id, secret \\ Dawarich.RailsSecret.fetch()),
    do: sign("ActiveStorage", ~s({"_rails":{"data":#{id},"pur":"blob_id"}}), :sha, secret)

  defp sign(salt, json, digest, secret) do
    data = Base.encode64(json)

    key =
      Plug.Crypto.KeyGenerator.generate(secret, salt,
        iterations: 1000,
        length: 64,
        digest: :sha256
      )

    data <> "--" <> Base.encode16(:crypto.mac(:hmac, digest, key, data), case: :lower)
  end
end
