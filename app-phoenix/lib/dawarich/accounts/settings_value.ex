defmodule Dawarich.Accounts.SettingsValue do
  @moduledoc false
  use Ecto.Type
  def type, do: :map
  def cast(value) when is_map(value) or is_nil(value), do: {:ok, value}
  def cast(_), do: :error
  def dump(value), do: cast(value)
  def load(value), do: {:ok, value}
end
