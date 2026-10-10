defmodule DawarichWeb.RouteVideoUpload do
  @moduledoc false

  alias Dawarich.{RailsMessages, RouteVideos, Storage}
  alias DawarichWeb.ActiveStorageUrls

  def target(scope, attrs, base_url, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    with {:ok, blob} <- RouteVideos.reserve_upload(scope, attrs, Keyword.put(opts, :now, now)) do
      service = Storage.service!(Storage.services!(System.get_env()), blob.service_name)
      {url, headers} = ActiveStorageUrls.direct_upload(service, blob, base_url, now)
      {:ok, %{url: url, headers: Map.new(headers), signed_id: RailsMessages.blob_id(blob.id)}}
    end
  end
end
