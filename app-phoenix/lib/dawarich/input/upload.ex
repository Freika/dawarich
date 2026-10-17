defmodule Dawarich.Input.Upload do
  @moduledoc false
  def cast(%{"file" => %Plug.Upload{} = upload}), do: {:ok, upload}
  def cast(_), do: :error
end
