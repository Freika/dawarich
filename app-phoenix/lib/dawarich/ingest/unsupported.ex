defmodule Dawarich.Ingest.Unsupported do
  @moduledoc false
  defexception [:reason]

  @impl true
  def message(%{reason: reason}), do: reason
end
