defmodule Dawarich.Accounts.Scope do
  @moduledoc false

  defstruct [:user, :locale]

  def for_user(nil, _locale), do: nil
  def for_user(user, locale), do: %__MODULE__{user: user, locale: locale}
end
