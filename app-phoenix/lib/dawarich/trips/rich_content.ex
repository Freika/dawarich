defmodule Dawarich.Trips.RichContent do
  @moduledoc false
  alias Dawarich.{HtmlSanitizer, TripDescription}

  @attributes ~w(sgid content-type url href filename filesize width height previewable presentation caption content)

  def read(nil), do: {:ok, nil}

  def read(body) when is_binary(body) and byte_size(body) <= 2_097_152 do
    case TripDescription.read(body) do
      {:ok, _} = supported ->
        supported

      :rails ->
        with {:ok, canonical} <- canonical(body),
             {:ok, rendered} <- render(canonical) do
          {:ok, if(String.trim(rendered) == "", do: nil, else: rendered)}
        end
    end
  end

  def read(_), do: :rails

  def canonical(body) when is_binary(body) do
    case TripDescription.read(body) do
      {:ok, normalized} -> {:ok, normalized}
      :rails -> canonical_tree(body)
    end
  end

  defp canonical_tree(body) do
    tree = LazyHTML.from_fragment(body) |> LazyHTML.to_tree()

    case convert(tree, 0) do
      {:ok, nodes} -> {:ok, LazyHTML.Tree.to_html(nodes)}
      _ -> :rails
    end
  rescue
    _ -> :rails
  end

  defp convert(_nodes, depth) when depth > 64, do: :rails
  defp convert(nodes, depth), do: map_nodes(nodes, &convert_node(&1, depth))
  defp convert_node(text, _depth) when is_binary(text), do: {:ok, text}
  defp convert_node({:comment, _} = comment, _depth), do: {:ok, comment}

  defp convert_node({"figure", attrs, _children} = node, depth) do
    case List.keyfind(attrs, "data-trix-attachment", 0) do
      {_, json} ->
        with {:ok, data} when is_map(data) <- Jason.decode(json) do
          attributes =
            Enum.map(data, fn {key, value} ->
              {Macro.underscore(key) |> String.replace("_", "-"), to_string(value)}
            end)

          convert_node({"action-text-attachment", attributes, []}, depth)
        else
          _ -> :rails
        end

      nil ->
        ordinary(node, depth)
    end
  end

  defp convert_node({"action-text-attachment", attrs, _children}, _depth) do
    attrs = Enum.filter(attrs, fn {key, _} -> key in @attributes end)
    type = attr(attrs, "content-type") || ""

    if attr(attrs, "sgid") == nil and String.starts_with?(type, "image/") and
         safe_image?(attr(attrs, "url")),
       do: {:ok, {"action-text-attachment", attrs, []}},
       else: :rails
  end

  defp convert_node(node, depth), do: ordinary(node, depth)

  defp ordinary({tag, attrs, children}, depth) do
    with {:ok, children} <- convert(children, depth + 1), do: {:ok, {tag, attrs, children}}
  end

  defp render(body) do
    nodes = LazyHTML.from_fragment(body) |> LazyHTML.to_tree()
    render_nodes(nodes)
  end

  defp render_nodes(nodes) do
    Enum.reduce_while(nodes, {:ok, ""}, fn node, {:ok, html} ->
      case render_node(node) do
        {:ok, part} -> {:cont, {:ok, html <> part}}
        _ -> {:halt, :rails}
      end
    end)
  end

  defp render_node({"action-text-attachment", attrs, []}) do
    url = attr(attrs, "url")

    dimensions =
      for key <- ~w(width height),
          value = attr(attrs, key),
          value,
          do: " #{key}=\"#{escape(value)}\""

    attachment = LazyHTML.Tree.to_html([{"action-text-attachment", attrs, []}])

    figure =
      "<figure class=\"attachment attachment--preview\">\n  <img src=\"#{escape(url)}\"#{Enum.join(dimensions)}>\n</figure>"

    {:ok,
     String.replace(
       attachment,
       "</action-text-attachment>",
       figure <> "</action-text-attachment>"
     )}
  end

  defp render_node(node) do
    if attachment?(node) do
      {tag, attrs, children} = node

      with {:ok, inner} <- render_nodes(children) do
        empty = sanitize(LazyHTML.Tree.to_html([{tag, attrs, []}]))

        if empty == "",
          do: {:ok, inner},
          else: {:ok, String.replace(empty, "</#{tag}>", inner <> "</#{tag}>")}
      end
    else
      {:ok, sanitize(LazyHTML.Tree.to_html([node]))}
    end
  end

  defp attachment?({"action-text-attachment", _, _}), do: true
  defp attachment?({_, _, children}), do: Enum.any?(children, &attachment?/1)
  defp attachment?(_), do: false

  defp sanitize(html) do
    html
    |> HtmlSanitizer.sanitize()
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> Enum.map_join(&serialize/1)
  end

  defp serialize(text) when is_binary(text),
    do:
      text
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")
      |> String.replace("\u00a0", "&nbsp;")

  defp serialize({tag, attrs, children}) do
    empty = LazyHTML.Tree.to_html([{tag, attrs, []}]) |> String.replace_suffix("/>", ">")

    String.replace_suffix(
      empty,
      "</#{tag}>",
      Enum.map_join(children, &serialize/1) <> "</#{tag}>"
    )
  end

  defp attr(attrs, key), do: attrs |> List.keyfind(key, 0) |> then(&(&1 && elem(&1, 1)))
  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp safe_image?(url) when is_binary(url) do
    sanitized = HtmlSanitizer.sanitize("<img src=\"#{escape(url)}\">")
    String.contains?(sanitized, "src=")
  end

  defp safe_image?(_), do: false

  defp map_nodes(nodes, fun) do
    Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
      case fun.(node) do
        {:ok, value} -> {:cont, {:ok, acc ++ [value]}}
        _ -> {:halt, :rails}
      end
    end)
  end
end
