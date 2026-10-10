defmodule Dawarich.Test.UploadCleanupHttp do
  @moduledoc false
  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, body, _headers, opts),
    do: Keyword.fetch!(opts, :respond).(method, url, body)
end
