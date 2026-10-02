defmodule DawarichWeb.BlobPath do
  @moduledoc false

  @kept ~c"!$&'()*+,;=:@"
  @kept_path [?/ | @kept]

  def redirect_path(blob_id, filename, opts \\ []) do
    disposition = Keyword.get(opts, :disposition, "attachment")
    secret = Keyword.get_lazy(opts, :secret, &Dawarich.RailsSecret.fetch/0)

    "/rails/active_storage/blobs/redirect/" <>
      escape(Dawarich.RailsMessages.blob_id(blob_id, secret), @kept) <>
      "/" <> escape(sanitize(filename), @kept_path) <> query(disposition)
  end

  defp query(nil), do: ""
  defp query(disposition), do: "?disposition=#{disposition}"

  defp sanitize(filename) do
    filename
    |> then(&Regex.replace(~r/\A[\x09-\x0D\x20]+|[\x09-\x0D\x20]+\z/, &1, ""))
    |> then(&Regex.replace(~r/[\x{202E}%$|:;\/<>?*"\t\r\n\\]/u, &1, "-"))
  end

  defp escape(value, keep), do: URI.encode(value, &(URI.char_unreserved?(&1) or &1 in keep))
end
