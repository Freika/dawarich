defmodule Dawarich.Points.Pages do
  @moduledoc false
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.{PointList, RubyInteger}

  def load(scope, params, opts \\ []) do
    with {:ok, scope} <- DataAccess.admit(scope, settings: true),
         {:ok, query, search} <- normalize(params, opts) do
      now = Keyword.get(opts, :now, DateTime.utc_now())

      options =
        opts
        |> Keyword.put_new(:self_hosted, Dawarich.ReleaseMigration.self_hosted?(System.get_env()))
        |> Keyword.merge(native: true, import_search: search)

      case PointList.load_query(scope.user, query, now, options) do
        {:ok, page} ->
          revision =
            :crypto.hash(:sha256, :erlang.term_to_binary({query.params, page.rows, page.count}))
            |> Base.encode16(case: :lower)

          unit = get_in(Dawarich.UserSettings.get(scope.user), ["maps", "distance_unit"]) || "km"

          {:ok,
           Map.merge(%{page | rows: project_rows(page.rows)}, %{
             query:
               if(search == "",
                 do: query.params,
                 else: Map.put(query.params, "import_search", search)
               ),
             revision: revision,
             unit: unit
           })}

        :not_found ->
          {:error, :not_found}

        _ ->
          {:error, :invalid_input}
      end
    end
  end

  def normalize(params, opts \\ [])

  def normalize(params, opts) when is_map(params) do
    search = params["import_search"] || ""
    values = Map.delete(params, "import_search")

    with true <- is_binary(search) and byte_size(search) <= 256,
         true <-
           Enum.all?(values, fn {_k, v} -> is_nil(v) or (is_binary(v) and byte_size(v) <= 128) end),
         {:ok, query} <- PointList.normalize(values, Keyword.put(opts, :native, true)) do
      {:ok, query, search}
    else
      _ -> {:error, :invalid_input}
    end
  end

  def normalize(_, _), do: {:error, :invalid_input}

  def selection(scope, params, ids, opts \\ []) do
    with :ok <- selection_shape(ids),
         {:ok, page} <- load(scope, params, opts) do
      ids = ids |> Enum.reject(&(&1 == "")) |> Enum.map(&RubyInteger.to_i/1) |> Enum.uniq()
      allowed = MapSet.new(page.rows, & &1.id)

      if Enum.all?(ids, &MapSet.member?(allowed, &1)),
        do: {:ok, ids},
        else: {:error, :unauthorized}
    end
  end

  def address(scope, value) do
    with {:ok, scope} <- DataAccess.admit(scope),
         true <- is_binary(value),
         id = RubyInteger.to_i(value),
         true <- id in 1..9_223_372_036_854_775_807 do
      case PointList.address(scope.user, id) do
        {:ok, address} -> {:ok, address}
        _ -> {:error, :not_found}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_input}
    end
  end

  defp project_rows(rows) do
    Enum.map(rows, fn row ->
      properties =
        Dawarich.Geocoding.Normalizer.from_data(row.geodata).properties
        |> Map.take(~w(street city country))

      %{row | geodata: %{"properties" => properties}}
    end)
  end

  defp selection_shape(ids) when is_list(ids) and length(ids) > 50, do: {:error, :limit}

  defp selection_shape(ids) when is_list(ids) do
    if Enum.all?(ids, &(is_binary(&1) and byte_size(&1) <= 32)),
      do: :ok,
      else: {:error, :invalid_input}
  end

  defp selection_shape(_), do: {:error, :invalid_input}
end
