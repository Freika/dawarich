defmodule Dawarich.Geocoding.HookRepo do
  @moduledoc false

  alias Dawarich.ScratchRepo

  def set_hook(fun), do: :persistent_term.put(__MODULE__, fun)
  def clear_hook, do: :persistent_term.erase(__MODULE__)

  def query!(sql, params \\ [], opts \\ []) do
    hook(sql, params)
    ScratchRepo.query!(sql, params, opts)
  end

  def query(sql, params \\ [], opts \\ []) do
    hook(sql, params)
    ScratchRepo.query(sql, params, opts)
  end

  def transaction(fun, opts \\ []), do: ScratchRepo.transaction(fun, opts)
  def rollback(value), do: ScratchRepo.rollback(value)

  defp hook(sql, params),
    do: :persistent_term.get(__MODULE__, fn _sql, _params -> :ok end).(sql, params)
end
