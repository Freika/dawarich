defmodule Dawarich.Test.NativeAdminUI do
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser

  def setup! do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Map.new(~w(SELF_HOSTED DAWARICH_RAILS), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("DAWARICH_RAILS", "off")

    ExUnit.Callbacks.on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    Dawarich.State.put_registration_enabled(Repo, true)

    RailsUser.insert!(%{
      id: 10801,
      email: "native-admin@example.invalid",
      admin: true,
      api_key: "synthetic-actor-key",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    RailsUser.insert!(%{
      id: 10802,
      email: "native-target@example.invalid",
      admin: false,
      api_key: "synthetic-target-key",
      settings: %{"timezone" => "UTC"}
    })

    %{actor: Accounts.get(10801), target: Accounts.get(10802)}
  end

  def conn(user), do: RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id)

  def html(view),
    do: rendered_to_string(view.module.render(:sys.get_state(view.pid).socket.assigns))

  def escaped(key, args \\ %{}),
    do:
      DawarichWeb.Translate.t("en", key, args)
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

  def labels(html) do
    doc = LazyHTML.from_document(html)

    for control <-
          doc
          |> LazyHTML.query(
            "input:not([type=hidden]):not([type=submit]):not([type=button]), select, textarea"
          )
          |> LazyHTML.filter(":not(label *):not([aria-label]):not([aria-labelledby])"),
        id = List.first(LazyHTML.attribute(control, "id")),
        is_nil(id) or Enum.count(LazyHTML.query(doc, ~s(label[for="#{id}"]))) != 1,
        do: LazyHTML.to_html(control)
  end

  def queries(fun) do
    id = "admin-ui-#{System.unique_integer([:positive])}"
    :telemetry.attach(id, [:dawarich, :repo, :query], &__MODULE__.query/4, self())

    try do
      result = fun.()
      {result, drain([])}
    after
      :telemetry.detach(id)
    end
  end

  def query(_, _, metadata, pid), do: send(pid, {:admin_ui_query, metadata.query})

  defp drain(acc) do
    receive do
      {:admin_ui_query, sql} -> drain([sql | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
