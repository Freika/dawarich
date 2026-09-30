defmodule DawarichWeb.BlobPath do
  @moduledoc false

  @kept ~c"-._~!$&'()*+,;=:@/"

  def redirect_path(blob_id, filename) do
    "/rails/active_storage/blobs/redirect/" <>
      Dawarich.RailsMessages.blob_id(blob_id) <>
      "/" <> URI.encode(sanitize(filename), &kept?/1) <> "?disposition=attachment"
  end

  defp sanitize(filename) do
    filename
    |> then(&Regex.replace(~r/\A[\x09-\x0D\x20]+|[\x09-\x0D\x20]+\z/, &1, ""))
    |> then(&Regex.replace(~r/[\x{202E}%$|:;\/<>?*"\t\r\n\\]/u, &1, "-"))
  end

  defp kept?(byte), do: byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9 or byte in @kept
end
