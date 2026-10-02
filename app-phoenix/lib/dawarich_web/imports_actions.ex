defmodule DawarichWeb.ImportsActions do
  @moduledoc false
  alias DawarichWeb.ImportsContext

  def delete(user, id) do
    case Dawarich.Imports.UiRecords.get(ImportsContext.repo(), user.id, id) do
      {:ok, %{source: 4} = record} ->
        Dawarich.Imports.Destroy.enqueue(
          ImportsContext.repo(),
          user.id,
          record.id,
          ImportsContext.for_user(user)
        )

      {:ok, _record} ->
        {:error, :rails_format}

      error ->
        error
    end
  end
end
