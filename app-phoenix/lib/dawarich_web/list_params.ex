defmodule DawarichWeb.ListParams do
  @moduledoc false

  def parse(params, query_string, sortable) do
    sort_by = params["sort_by"]

    %{
      column: if(is_binary(sort_by) and sort_by in sortable, do: sort_by, else: "created_at"),
      direction: if(params["order_by"] == "asc", do: :asc, else: :desc),
      page: max(DawarichWeb.Params.ruby_to_i(params["page"]), 1),
      current_sort: current_sort(params, query_string)
    }
  end

  def sort_href(path, column, %{current_sort: current, direction: direction}) do
    next = if current == column and direction == :asc, do: "desc", else: "asc"
    path <> "?order_by=" <> next <> "&sort_by=" <> column
  end

  defp current_sort(params, query_string) do
    if Map.has_key?(params, "sort_by") and not bare?(query_string, "sort_by"),
      do: params["sort_by"],
      else: "created_at"
  end

  defp bare?(query_string, key) do
    query_string
    |> String.split("&")
    |> Enum.filter(&(URI.decode_www_form(hd(String.split(&1, "=", parts: 2))) == key))
    |> List.last()
    |> then(&(&1 != nil and not String.contains?(&1, "=")))
  end
end
