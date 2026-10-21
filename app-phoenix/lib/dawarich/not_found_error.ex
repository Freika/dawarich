defmodule Dawarich.NotFoundError do
  defexception message: "not found", plug_status: 404
end
