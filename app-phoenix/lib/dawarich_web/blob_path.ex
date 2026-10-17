defmodule DawarichWeb.BlobPath do
  @moduledoc false
  defdelegate redirect_path(arg1, arg2), to: Dawarich.Storage.BlobPath
  defdelegate redirect_path(arg1, arg2, arg3), to: Dawarich.Storage.BlobPath
  defdelegate segment(arg1), to: Dawarich.Storage.BlobPath
  defdelegate path(arg1), to: Dawarich.Storage.BlobPath
end
