defmodule Dawarich.Auth.RememberCredential do
  @moduledoc false
  alias Dawarich.Auth.Remember

  def valid?(user, payload, now),
    do: Remember.valid?(user, payload, now)
end
