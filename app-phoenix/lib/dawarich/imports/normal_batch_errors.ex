defmodule Dawarich.Imports.NormalBatchErrors do
  @moduledoc false
  alias Dawarich.Imports.Fence
  alias Dawarich.{I18n, Notifications}

  def notify!(import, context, error) do
    name = Map.fetch!(context, :importer_name)

    {:ok, title} =
      I18n.t(context.locale, "services.imports.bulk_insertable.importer_name_import_error", %{
        "importer_name" => name
      })

    Fence.run(context, fn ->
      Notifications.create!(
        context.repo,
        import.user_id,
        :error,
        title,
        "Failed to process #{name} data: #{message(error)}",
        naive(clock(context.now))
      )
    end)
  end

  def message(%Postgrex.Error{postgres: %{code: code, message: message} = data}) do
    class = code |> Atom.to_string() |> Macro.camelize()

    "PG::#{class}: ERROR:  #{message}\n" <>
      Enum.map_join([:detail, :hint, :where], fn key ->
        label = if key == :where, do: "CONTEXT", else: key |> Atom.to_string() |> String.upcase()
        if data[key], do: "#{label}:  #{data[key]}\n", else: ""
      end)
  end

  def message(error), do: Exception.message(error)
  defp clock(fun) when is_function(fun, 0), do: fun.()
  defp clock(now), do: now
  defp naive(%DateTime{} = now), do: DateTime.to_naive(now)
  defp naive(%NaiveDateTime{} = now), do: now
end
