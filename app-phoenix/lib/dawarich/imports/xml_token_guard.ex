defmodule Dawarich.Imports.XmlTokenGuard do
  @moduledoc false
  @limit 1_048_576
  @prefixes ["<!--", "<![CDATA[", "<!DOCTYPE", "<?"]

  def new(opts \\ []),
    do: %{
      mode: :text,
      size: 0,
      marker: "",
      quote: nil,
      streamed_text: Keyword.get(opts, :streamed_text, false)
    }

  defp reset(s), do: new(streamed_text: s.streamed_text)
  def feed(bytes, state), do: scan(bytes, state)
  defp scan(<<>>, state), do: state

  defp scan(<<byte, rest::binary>>, s) do
    size = if s.streamed_text and s.mode in [:text, :cdata], do: 0, else: s.size + 1
    s = %{s | size: size}
    if s.size > @limit, do: raise(ArgumentError, "GPX parse error: XML token exceeds limit")
    scan(rest, step(byte, s))
  end

  defp step(?<, %{mode: :text} = s), do: %{reset(s) | mode: :open, size: 1, marker: "<"}
  defp step(_, %{mode: :text} = s), do: s

  defp step(c, %{mode: :open} = s) do
    marker = s.marker <> <<c>>

    cond do
      marker == "<!DOCTYPE" -> raise ArgumentError, "GPX parse error: DTD is not allowed"
      marker == "<!--" -> %{s | mode: :comment, marker: ""}
      marker == "<![CDATA[" -> %{s | mode: :cdata, marker: ""}
      marker == "<?" -> %{s | mode: :pi, marker: ""}
      Enum.any?(@prefixes, &String.starts_with?(&1, marker)) -> %{s | marker: marker}
      true -> step(c, %{s | mode: :tag, marker: ""})
    end
  end

  defp step(c, %{mode: :tag, quote: nil} = s) when c in [?', ?"], do: %{s | quote: c}
  defp step(c, %{mode: :tag, quote: c} = s), do: %{s | quote: nil}
  defp step(?>, %{mode: :tag, quote: nil} = s), do: reset(s)
  defp step(_, %{mode: :tag} = s), do: s

  defp step(c, s) do
    marker = s.marker <> <<c>>
    ending = %{comment: "-->", cdata: "]]>", pi: "?>"}[s.mode]

    if String.ends_with?(marker, ending),
      do: reset(s),
      else: %{
        s
        | marker: binary_part(marker, max(byte_size(marker) - 2, 0), min(byte_size(marker), 2))
      }
  end
end
