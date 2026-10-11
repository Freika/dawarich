defmodule Dawarich.Storage.BlobPath do
  @moduledoc false
  @kept ~c"!$&'()*+,;=:@"
  @kept_path [47 | @kept]
  def redirect_path(blob_id, filename, opts \\ []) do
    disposition = Keyword.get(opts, :disposition, "attachment")
    secret = Keyword.get_lazy(opts, :secret, &Dawarich.RailsSecret.fetch/0)

    "/rails/active_storage/blobs/redirect/" <>
      segment(Dawarich.RailsMessages.blob_id(blob_id, secret)) <>
      "/" <> path(Dawarich.Storage.sanitized_filename(filename)) <> query(disposition)
  end

  def segment(value) do
    escape(value, @kept)
  end

  def path(value) do
    escape(value, @kept_path)
  end

  defp query(nil) do
    ""
  end

  defp query(disposition) do
    "?disposition=#{disposition}"
  end

  defp escape(value, keep) do
    URI.encode(value, &(URI.char_unreserved?(&1) or &1 in keep))
  end
end
