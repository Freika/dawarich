defmodule Dawarich.Test.DataPageParity do
  @moduledoc false

  def action_paths(html, mode \\ :document) do
    parsed =
      if mode == :fragment, do: LazyHTML.from_fragment(html), else: LazyHTML.from_document(html)

    parsed |> LazyHTML.to_tree() |> restore_paths() |> LazyHTML.from_tree() |> LazyHTML.to_html()
  end

  def resilience(html) do
    for {native, rails} <- [
          {"w-full min-w-0 my-5", "w-full my-5"},
          {"mx-auto md:w-2/3 w-full min-w-0 flex", "mx-auto md:w-2/3 w-full flex"},
          {"mx-auto min-w-0 max-w-full", "mx-auto"},
          {"btn btn-primary h-auto min-h-12 whitespace-normal", "btn btn-primary"},
          {"btn mt-2 max-w-full h-auto min-h-12 whitespace-normal", "btn mt-2"},
          {"btn btn-outline btn-error mt-2 max-w-full h-auto min-h-12 whitespace-normal",
           "btn btn-outline btn-error mt-2"},
          {"btn mt-2 ml-2 max-w-full h-auto min-h-12 whitespace-normal", "btn mt-2 ml-2"},
          {"inline-block ml-2 max-w-full", "inline-block ml-2"},
          {"flex items-center gap-2 mb-2 flex-wrap", "flex items-center gap-2 mb-2"},
          {"modal-box max-w-xl min-w-0 [overflow-wrap:anywhere]", "modal-box max-w-xl"},
          {"modal-action flex-wrap", "modal-action"}
        ],
        reduce: html do
      html -> String.replace(html, ~s(class="#{native}"), ~s(class="#{rails}"))
    end
    |> String.replace(~r/(<div id="import_[0-9]+") class="overflow-x-auto"/, "\\1")
    |> String.replace(~s(<div class="min-w-0">), "<div>")
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
