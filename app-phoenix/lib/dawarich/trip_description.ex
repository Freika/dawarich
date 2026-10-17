defmodule Dawarich.TripDescription do
  @moduledoc false

  @blocks ~w(div h1 blockquote pre ul ol)
  @lists ~w(ul ol)
  @flow [:root, "div", "blockquote", "li"]
  @max_depth 16
  @open ~r/\A<(div|h1|blockquote|pre|ul|ol|li|strong|em|del)>|\A<a href="https?:\/\/(?:[A-Za-z0-9\-._~:\/?#\[\]@!$'()*+,;=%]|&amp;)+">/
  @text ~r/\A(?:[^<>&]+|&(?:amp|lt|gt|nbsp);)+/
  @forbidden ~r/(?![ \n])[\p{Cc}\p{Z}\x{FEFF}]/u
  @strip ~r/\A[\t\n\x0B\f\r ]+|(?<![\t\n\x0B\f\r ])[\t\n\x0B\f\r ]+\z/

  def read(nil), do: {:ok, nil}

  def read(body) do
    case String.replace(body, @strip, "") do
      "" -> {:ok, nil}
      html -> if scan(html, [:root]) and not (html =~ @forbidden), do: {:ok, html}, else: :rails
    end
  end

  def html(description), do: ["<div class=\"trix-content\">\n  ", description, "\n\n</div>\n"]

  defp scan("", stack), do: stack == [:root]

  defp scan("</" <> rest, [tag | stack]) when is_binary(tag) do
    close = tag <> ">"
    String.starts_with?(rest, close) and scan(drop(rest, byte_size(close)), stack)
  end

  defp scan("<br>" <> rest, [parent | _] = stack), do: parent not in @lists and scan(rest, stack)

  defp scan("<" <> _ = html, [parent | _] = stack) do
    case Regex.run(@open, html) do
      [open, tag] ->
        allowed?(tag, parent) and pre?(tag, html, open) and push(html, open, tag, stack)

      [open] ->
        "a" not in stack and parent not in @lists and push(html, open, "a", stack)

      nil ->
        false
    end
  end

  defp scan(text, [parent | _] = stack) do
    case Regex.run(@text, text) do
      [run] when parent not in @lists -> scan(drop(text, byte_size(run)), stack)
      _ -> false
    end
  end

  defp allowed?("li", parent), do: parent in @lists
  defp allowed?(_tag, parent) when parent in @lists, do: false
  defp allowed?(tag, parent) when tag in @blocks, do: parent in @flow
  defp allowed?(_tag, _parent), do: true

  defp pre?("pre", html, open), do: not String.starts_with?(drop(html, byte_size(open)), "\n")
  defp pre?(_tag, _html, _open), do: true

  defp push(html, open, tag, stack),
    do: length(stack) <= @max_depth and scan(drop(html, byte_size(open)), [tag | stack])

  defp drop(binary, n), do: binary_part(binary, n, byte_size(binary) - n)
end
