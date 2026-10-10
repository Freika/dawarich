defmodule DawarichWeb.ImportsActions do
  @moduledoc false
  alias DawarichWeb.ImportsContext

  def delete(user, id) do
    case Dawarich.Imports.UiRecords.get(ImportsContext.repo(), user.id, id) do
      {:ok, record} ->
        if DawarichWeb.ImportsGate.admitted?(record) do
          Dawarich.Imports.Destroy.enqueue(
            ImportsContext.repo(),
            user.id,
            record.id,
            ImportsContext.for_user(user)
          )
        else
          {:error, :rails_format}
        end

      error ->
        error
    end
  end
end
