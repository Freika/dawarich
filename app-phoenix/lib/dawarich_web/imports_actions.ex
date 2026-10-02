defmodule DawarichWeb.ImportsActions do
  @moduledoc false
  alias DawarichWeb.ImportsContext

  def delete(user, id) do
    with {:ok, record} <- Dawarich.Imports.UiRecords.get(ImportsContext.repo(), user.id, id) do
      Dawarich.Imports.Destroy.enqueue(
        ImportsContext.repo(),
        user.id,
        record.id,
        ImportsContext.for_user(user)
      )
    end
  end
end
