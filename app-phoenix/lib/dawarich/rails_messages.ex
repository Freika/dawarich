defmodule Dawarich.RailsMessages do
  @moduledoc false

  def blob_id(id, secret \\ Dawarich.RailsSecret.fetch()) do
    data = Base.encode64(~s({"_rails":{"data":#{id},"pur":"blob_id"}}))
    key = Dawarich.RailsCookies.key(secret, "ActiveStorage", 64)
    data <> "--" <> Base.encode16(:crypto.mac(:hmac, :sha, key, data), case: :lower)
  end
end
