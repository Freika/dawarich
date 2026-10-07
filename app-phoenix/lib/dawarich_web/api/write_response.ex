defmodule DawarichWeb.Api.WriteResponse do
  @moduledoc false
  alias Dawarich.Repo
  alias DawarichWeb.Api.Respond

  def call(conn, write) do
    render = get_in(conn.assigns, [:api_context, :render_response]) || (&Respond.encode/1)

    result =
      Repo.transaction(fn ->
        {kind, status, body} = write.()
        rendered = Respond.prepare_encoded_json(conn, status, render.(body))
        if kind == :error, do: Repo.rollback(rendered), else: rendered
      end)

    {_, rendered} = result
    Respond.send_prepared(rendered)
  end
end
