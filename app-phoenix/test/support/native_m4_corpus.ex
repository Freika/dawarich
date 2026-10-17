defmodule Dawarich.Test.NativeM4Corpus do
  @moduledoc false
  import Kernel, except: [node: 1]

  def prepare(html) do
    html
    |> then(fn value ->
      if String.contains?(value, ["<html", "<body", "<head"]),
        do: LazyHTML.from_document(value),
        else: LazyHTML.from_fragment(value)
    end)
    |> LazyHTML.to_tree()
    |> Enum.flat_map(&node/1)
    |> LazyHTML.from_tree()
    |> LazyHTML.to_html()
  end

  def reports(html) do
    doc = LazyHTML.from_fragment(html)

    dropped =
      doc
      |> LazyHTML.query(
        "dialog#sharing_modal, [onclick='sharing_modal.showModal()'], a[href$='/sharing'], a.btn.h-auto.whitespace-normal[href*='utm_content=sharing']"
      )
      |> LazyHTML.to_tree()

    doc |> LazyHTML.to_tree() |> prune(dropped) |> LazyHTML.from_tree() |> LazyHTML.to_html()
  end

  defp prune(nodes, dropped) when is_list(nodes),
    do: for(node <- nodes, node not in dropped, do: prune(node, dropped))

  defp prune({tag, attrs, children}, dropped), do: {tag, attrs, prune(children, dropped)}
  defp prune(other, _), do: other

  defp node({"form", attrs, children} = original) do
    values = Map.new(attrs)

    case {values["action"], values["data-card-modal-target"]} do
      {"/imports", _} ->
        [{"native-upload-entry", [{"href", "/imports/new"}], []}]

      {"/achievements/" <> rest, "createForm"} ->
        key = String.replace_suffix(rest, "/toggle_sharing", "")

        [
          {"a",
           [{"href", "/achievements/" <> key <> "/sharing"}, {"class", "btn btn-sm btn-primary"}],
           ["managed-sharing"]}
        ]

      {"/achievements/" <> _, "disableForm"} ->
        []

      _ ->
        ordinary(original, children)
    end
  end

  defp node({"turbo-frame", attrs, children} = original) do
    if Map.new(attrs)["id"] == "share-link-modal" and
         Enum.all?(children, &(is_binary(&1) and String.trim(&1) == "")),
       do: [],
       else: ordinary(original, children)
  end

  defp node({tag, attrs, children} = original) do
    values = Map.new(attrs)

    cond do
      tag == "div" and values["class"] == "flex justify-end" and
          Enum.any?(children, fn
            {"a", a, _} -> Map.new(a)["href"] == "/imports/new"
            _ -> false
          end) ->
        [{"native-upload-entry", [{"href", "/imports/new"}], []}]

      tag == "a" and Regex.match?(~r|^/achievements/[^/]+/sharing$|, values["href"] || "") ->
        [
          {"a", [{"href", values["href"]}, {"class", "btn btn-sm btn-primary"}],
           ["managed-sharing"]}
        ]

      values["class"] == "ach-modal-unshare" ->
        [
          {"a",
           [
             {"class", "ach-modal-unshare"},
             {"data-card-modal-target", "unshareBtn"},
             {"hidden", ""}
           ], children}
        ]

      true ->
        ordinary(original, children)
    end
  end

  defp node(other), do: [other]

  defp ordinary({tag, attrs, _}, children) do
    values = Map.new(attrs)

    attrs =
      if Regex.match?(~r{^/(trips|tracks)/[^/]+/share_link/new$}, values["href"] || "") or
           String.starts_with?(values["href"] || "", "/share_links/hub"),
         do: Enum.reject(attrs, fn {key, _} -> key in ~w(data-turbo data-turbo-frame) end),
         else: attrs

    attrs =
      Enum.map(attrs, fn
        {"data-share-manager", path} ->
          {"data-share-toggle", String.replace_suffix(path, "/sharing", "/toggle_sharing")}

        {"id", "family-navbar-indicator-mobile"} ->
          {"id", "family-navbar-indicator"}

        pair ->
          pair
      end)

    [{tag, attrs, Enum.flat_map(children, &node/1)}]
  end
end
