defmodule DawarichWeb.ActiveStorageUrls do
  @moduledoc false
  defdelegate binary_types(), to: Dawarich.Storage.UploadUrls
  defdelegate inline_types(), to: Dawarich.Storage.UploadUrls
  defdelegate service_url(arg1, arg2, arg3, arg4, arg5), to: Dawarich.Storage.UploadUrls
  defdelegate direct_upload(arg1, arg2, arg3, arg4), to: Dawarich.Storage.UploadUrls
end
