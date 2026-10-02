defmodule Dawarich.Auth.RememberCredential do
  @moduledoc false
  alias Dawarich.Accounts

  def valid?(user, payload, now),
    do: Accounts.remembered?(user, payload, now) and Accounts.unlocked?(user, now)
end
