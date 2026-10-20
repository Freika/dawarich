defmodule Dawarich.Test.DataPageParity do
  @moduledoc false

  def action_paths(html, mode \\ :document) do
    parsed =
      if mode == :fragment, do: LazyHTML.from_fragment(html), else: LazyHTML.from_document(html)

    parsed |> LazyHTML.to_tree() |> restore_paths() |> LazyHTML.from_tree() |> LazyHTML.to_html()
  end

  defp restore_paths(nodes) when is_list(nodes), do: Enum.map(nodes, &restore_paths/1)

  defp restore_paths({tag, attrs, children}) do
    path = List.keyfind(attrs, "data-native-href", 0)

    attrs =
      if (tag == "a" and {"href", "#"} in attrs and path) &&
           List.keymember?(attrs, "phx-click", 0),
         do: List.keyreplace(attrs, "href", 0, {"href", elem(path, 1)}),
         else: attrs

    {tag, attrs, restore_paths(children)}
  end

  defp restore_paths(other), do: other
end
