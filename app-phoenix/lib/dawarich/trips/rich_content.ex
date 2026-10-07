defmodule Dawarich.Trips.RichContent do
  @moduledoc false
  alias Dawarich.{HtmlSanitizer, TripDescription}
  alias Dawarich.Trips.Attachments

  @attributes ~w(sgid content-type url href filename filesize width height previewable presentation caption content)

  def read(body, repo \\ Dawarich.Repo)
  def read(nil, _repo), do: {:ok, nil}

  def read(body, repo) when is_binary(body) and byte_size(body) <= 2_097_152 do
    case TripDescription.read(body) do
      {:ok, _} = supported ->
        supported

      :rails ->
        with {:ok, canonical} <- canonical(body, repo),
             {:ok, rendered} <- render(canonical, repo) do
          {:ok, if(String.trim(rendered) == "", do: nil, else: rendered)}
        end
    end
  end

  def read(_, _repo), do: :rails

  def editor(body, repo \\ Dawarich.Repo) do
    with {:ok, html} <- read(body, repo) do
      {:ok, if(html, do: Attachments.editor(html), else: nil)}
    end
  end

  def canonical(body, repo \\ Dawarich.Repo)

  def canonical(body, repo) when is_binary(body) and byte_size(body) <= 2_097_152 do
    case TripDescription.read(body) do
      {:ok, normalized} -> {:ok, normalized}
      :rails -> canonical_tree(body, repo)
    end
  end

  def canonical(_, _repo), do: :rails

  defp canonical_tree(body, repo) do
    tree = LazyHTML.from_fragment(body) |> LazyHTML.to_tree()

    case convert(tree, 0, repo) do
      {:ok, nodes} -> {:ok, LazyHTML.Tree.to_html(nodes)}
      _ -> :rails
    end
  rescue
    _ -> :rails
  end

  defp convert(_nodes, depth, _repo) when depth > 64, do: :rails
  defp convert(nodes, depth, repo), do: map_nodes(nodes, &convert_node(&1, depth, repo))
  defp convert_node(text, _depth, _repo) when is_binary(text), do: {:ok, text}
  defp convert_node({:comment, _} = comment, _depth, _repo), do: {:ok, comment}

  defp convert_node({"figure", attrs, _children} = node, depth, repo) do
    case List.keyfind(attrs, "data-trix-attachment", 0) do
      {_, json} ->
        with {:ok, data} when is_map(data) <- Jason.decode(json),
             {:ok, composed} when is_map(composed) <-
               Jason.decode(attr(attrs, "data-trix-attributes") || "{}") do
          attributes =
            Enum.map(Map.merge(data, composed), fn {key, value} ->
              {Macro.underscore(key) |> String.replace("_", "-"), to_string(value)}
            end)

          attributes =
            for key <- @attributes, pair = List.keyfind(attributes, key, 0), pair, do: pair

          convert_node({"action-text-attachment", attributes, []}, depth, repo)
        else
          _ -> :rails
        end

      nil ->
        ordinary(node, depth, repo)
    end
  end

  defp convert_node({"action-text-attachment", attrs, _children}, depth, repo) do
    attrs = Enum.filter(attrs, fn {key, _} -> key in @attributes end)
    type = attr(attrs, "content-type") || ""

    supported =
      cond do
        attr(attrs, "sgid") != nil ->
          Attachments.resolve(repo, attr(attrs, "sgid")) != :pending

        String.contains?(type, "html") and attr(attrs, "content") not in [nil, ""] ->
          match?(
            {:ok, _},
            convert(
              LazyHTML.from_fragment(attr(attrs, "content")) |> LazyHTML.to_tree(),
              depth + 1,
              repo
            )
          )

        true ->
          not String.starts_with?(type, "image/") or attr(attrs, "url") == nil or
            safe_image?(attr(attrs, "url"))
      end

    if supported and attrs != [], do: {:ok, {"action-text-attachment", attrs, []}}, else: :rails
  end

  defp convert_node(node, depth, repo), do: ordinary(node, depth, repo)

  defp ordinary({tag, attrs, children}, depth, repo) do
    with {:ok, children} <- convert(children, depth + 1, repo) do
      attrs = if tag == "div" and gallery?(children), do: [], else: attrs
      {:ok, {tag, attrs, children}}
    end
  end

  defp render(body, repo) do
    nodes = LazyHTML.from_fragment(body) |> LazyHTML.to_tree()
    render_nodes(nodes, repo)
  end

  defp render_nodes(nodes, repo, gallery \\ false) do
    Enum.reduce_while(nodes, {:ok, ""}, fn node, {:ok, html} ->
      case render_node(node, repo, gallery) do
        {:ok, part} -> {:cont, {:ok, html <> part}}
        _ -> {:halt, :rails}
      end
    end)
  end

  defp render_node({"action-text-attachment", attrs, []}, repo, gallery) do
    cond do
      sgid = attr(attrs, "sgid") ->
        case Attachments.resolve(repo, sgid) do
          {:ok, blob} ->
            {full, html} = Attachments.render(blob, attrs, gallery)
            {:ok, wrap(full, html)}

          status when status in [:missing, :invalid] ->
            fallback_attachment(attrs)

          _ ->
            :rails
        end

      true ->
        fallback_attachment(attrs)
    end
  end

  defp render_node(node, repo, _gallery) do
    if attachment?(node) do
      {tag, attrs, children} = node

      gallery = tag == "div" and gallery?(children)

      children = if gallery, do: Enum.filter(children, &is_tuple/1), else: children

      with {:ok, inner} <- render_nodes(children, repo, gallery) do
        if gallery do
          {:ok,
           "<div class=\"attachment-gallery attachment-gallery--#{length(children)}\">\n  #{inner}\n</div>\n"}
        else
          empty = sanitize(LazyHTML.Tree.to_html([{tag, attrs, []}]))

          if empty == "",
            do: {:ok, inner},
            else: {:ok, String.replace(empty, "</#{tag}>", inner <> "</#{tag}>")}
        end
      end
    else
      {:ok, sanitize(LazyHTML.Tree.to_html([node]))}
    end
  end

  defp fallback_attachment(attrs) do
    type = attr(attrs, "content-type") || ""

    cond do
      String.contains?(type, "html") and attr(attrs, "content") not in [nil, ""] ->
        :rails

      String.starts_with?(type, "image/") and safe_image?(attr(attrs, "url")) ->
        remote_image(attrs)

      true ->
        {:ok, wrap(attrs, "☒")}
    end
  end

  defp gallery?(children) do
    Enum.count(children, &is_tuple/1) >= 2 and
      Enum.all?(children, fn
        text when is_binary(text) -> Regex.match?(~r/\A[ \n]*\z/, text)
        {"action-text-attachment", attrs, _} -> attr(attrs, "presentation") == "gallery"
        _ -> false
      end)
  end

  defp wrap(attrs, html) do
    attrs =
      Enum.flat_map(attrs, fn
        {"href", value} ->
          HtmlSanitizer.sanitize("<a href=\"#{escape(value)}\"></a>")
          |> LazyHTML.from_fragment()
          |> LazyHTML.attribute("href")
          |> Enum.map(&{"href", &1})

        pair ->
          [pair]
      end)

    LazyHTML.Tree.to_html([
      {"action-text-attachment",
       Enum.sort_by(attrs, fn {key, _} -> Enum.find_index(@attributes, &(&1 == key)) end), []}
    ])
    |> String.replace("</action-text-attachment>", html <> "</action-text-attachment>")
  end

  defp remote_image(attrs) do
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
