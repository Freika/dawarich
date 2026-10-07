defmodule Dawarich.Geocoding.HookRepo do
  @moduledoc false

  alias Dawarich.ScratchRepo

  def set_hook(fun), do: :persistent_term.put(__MODULE__, fun)
  def clear_hook, do: :persistent_term.erase(__MODULE__)

  def query!(sql, params \\ [], opts \\ []) do
    {sql, params} = hooked_query(sql, params)
    ScratchRepo.query!(sql, params, opts)
  end

  def query(sql, params \\ [], opts \\ []) do
    {sql, params} = hooked_query(sql, params)
    ScratchRepo.query(sql, params, opts)
  end

  def insert!(changeset, opts \\ []), do: ScratchRepo.insert!(changeset, opts)

  def transaction(fun, opts \\ []), do: ScratchRepo.transaction(fun, opts)
  def in_transaction?, do: ScratchRepo.in_transaction?()
  def rollback(value), do: ScratchRepo.rollback(value)

  defp hook(sql, params),
    do: :persistent_term.get(__MODULE__, fn _sql, _params -> :ok end).(sql, params)

  defp hooked_query(sql, params) do
    case hook(sql, params) do
      {:query, replacement, values} -> {replacement, values}
      _ -> {sql, params}
    end
  end
end
