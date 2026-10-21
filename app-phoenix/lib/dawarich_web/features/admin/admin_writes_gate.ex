defmodule DawarichWeb.AdminWritesGate do
  @moduledoc false
  alias Dawarich.Auth.Admission

  def context(opts) do
    Keyword.get(opts, :context, %{})
    |> Map.put_new(:self_hosted, System.get_env("SELF_HOSTED") == "true")
    |> Map.put_new_lazy(:oidc, &Admission.oidc?/0)
  end

  def auth_options(context),
    do: if(context[:secret], do: [secret: context.secret], else: [])
end
