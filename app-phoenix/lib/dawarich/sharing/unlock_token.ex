defmodule Dawarich.Sharing.UnlockToken do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def proof_identity(token) when is_binary(token),
    do: :crypto.hash(:sha256, "native-public:" <> token) |> Base.encode16(case: :lower)

  def unlock_token(id, phrase) do
    unless Ruby.blank?(phrase),
      do: :sha256 |> :crypto.hash("#{id}:#{phrase}") |> Base.encode16(case: :lower)
  end
end
