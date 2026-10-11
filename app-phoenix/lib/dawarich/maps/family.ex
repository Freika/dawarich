defmodule Dawarich.Maps.Family do
  @moduledoc false
  alias Dawarich.Families

  def view(scope, opts \\ []) do
    with {:ok, %{state: :show} = page} <- Families.page(scope, :show, opts) do
      {:ok,
       %{
         presentation: page,
         config: %{
           "revision" => 1,
           "range" => %{"timezone" => Dawarich.UserTimeZone.name(scope.user.settings)}
         }
       }}
    else
      {:ok, _} -> {:error, :not_found}
      error -> error
    end
  end

  def read(scope, action, params, opts \\ []) do
    result =
      case action do
        :locations -> Families.locations(scope, opts)
        :history -> Families.history(scope, params, opts)
      end

    case result do
      {:ok, body} -> {:ok, 200, Map.delete(body, :deadline)}
      {:error, :unauthorized} -> {:ok, 404, %{error: "not_in_family"}}
      {:error, :expired} -> {:ok, 403, %{error: "family_unavailable"}}
      error -> error
    end
  end
end
