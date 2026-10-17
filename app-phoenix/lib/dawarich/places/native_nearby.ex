defmodule Dawarich.Places.NativeNearby do
  @moduledoc false
  alias Dawarich.Places.{Access, Nearby, NearbyInput}
  @fields ~w(name latitude longitude street city country)a

  def run(original, params, opts) do
    with {:ok, admitted} <- Access.admit(original),
         :ok <- Access.settings(admitted),
         {:ok, request} <- NearbyInput.parse(params),
         {:ok, scope} <- Access.admit(original) do
      fetch = opts[:fetch] || (&Nearby.fetch/6)

      results =
        fetch.(
          scope.user,
          request.latitude,
          request.longitude,
          request.radius,
          request.limit,
          opts
        )

      {:ok, project(results, request.limit)}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp project(results, limit) when is_list(results) do
    results
    |> Enum.filter(&is_map/1)
    |> Enum.take(limit)
    |> Enum.with_index()
    |> Enum.map(fn {result, index} ->
      for field <- @fields,
          into: %{index: index},
          do: {field, safe(result[Atom.to_string(field)])}
    end)
  end

  defp project(_, _), do: []
  defp safe(value) when is_binary(value), do: String.slice(value, 0, 1000)
  defp safe(value) when is_number(value), do: value
  defp safe(_), do: nil
end
