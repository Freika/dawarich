defmodule Dawarich.Test.FormIsolation do
  @moduledoc false
  import ExUnit.Assertions

  def assert_form_isolated(html, selector \\ "form:not([phx-submit]):not([phx-change])") do
    doc = LazyHTML.from_document(html)
    forms = doc |> LazyHTML.query(selector) |> LazyHTML.to_tree()
    assert forms != [], "no ordinary form matches #{selector}"
    ids = doc |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")
    walk(LazyHTML.to_tree(doc), forms, ids, false, nil)
    :ok
  end

  defp walk(nodes, forms, ids, selected, island) when is_list(nodes) do
    Enum.each(nodes, &walk(&1, forms, ids, selected, island))
  end

  defp walk({tag, attributes, children} = node, forms, ids, selected, island) do
    attrs = Map.new(attributes)
    selected = selected or node in forms
    island = if attrs["phx-update"] == "ignore", do: attrs["id"], else: island

    if selected and editable?(tag, attrs) do
      assert is_binary(island) and island != "",
             "#{tag} #{attrs["name"] || attrs["id"]} needs a stable id + phx-update=ignore island"

      assert Enum.count(ids, &(&1 == island)) == 1, "isolation id #{island} must be unique"
    end

    walk(children, forms, ids, selected, island)
  end

  defp walk(_node, _forms, _ids, _selected, _island), do: :ok

  defp editable?("input", attrs), do: attrs["type"] not in ~w(hidden submit button reset)
  defp editable?(tag, _attrs), do: tag in ~w(select textarea trix-editor)
end
