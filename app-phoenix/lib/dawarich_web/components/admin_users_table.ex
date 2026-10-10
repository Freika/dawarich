defmodule DawarichWeb.AdminUsersTable do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.HumanDatetime, only: [human_datetime: 1]
  alias DawarichWeb.NumberFormat
  alias Phoenix.LiveView.JS

  attr :locale, :string, required: true
  attr :rows, :list, required: true
  attr :actor, :map, required: true

  def table(assigns) do
    ~H"""
    <table class="table w-full">
      <thead>
        <tr>
          <th :for={key <- ~w(email role status points last_sign_in created_at)}>
            {t(@locale, "settings.users.index." <> key, %{})}
          </th><th></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={user <- @rows} data-user-id={user.id}>
          <td>
            <div>
              <.link
                class="font-bold underline hover:no-underline"
                navigate={"/settings/users/#{user.id}"}
              >{user.email}</.link>
            </div>
          </td>
          <td>
            <span class={if(user.admin, do: "badge badge-primary", else: "badge badge-ghost")}>{t(
              @locale,
              "settings.users.index." <> if(user.admin, do: "admin", else: "user"),
              %{}
            )}</span>
          </td>
          <td>
            <span :if={user.status in 0..2} class={"badge badge-" <> badge(user.status)}>{t(
              @locale,
              "settings.users.index." <> status(user.status),
              %{}
            )}</span>
          </td>
          <td>{NumberFormat.delimited(@locale, user.points_count || 0)}</td>
          <td>
            <%= if user.last_sign_in_at do %>
              <.human_datetime locale={@locale} at={user.last_sign_in_at} />
            <% else %>
              <span class="text-base-content/50">{t(@locale, "settings.users.index.never", %{})}</span>
            <% end %>
          </td>
          <td><.human_datetime locale={@locale} at={user.created_at} /></td>
          <td class="flex gap-2">
            <.link class="btn btn-ghost btn-sm" navigate={"/settings/users/#{user.id}/edit"}>{t(
              @locale,
              "settings.users.index.edit",
              %{}
            )}</.link>
            <button
              :if={user.id != @actor.id}
              class="btn btn-error btn-sm"
              phx-click={
                JS.push("open_delete", value: %{id: user.id})
                |> JS.dispatch("dawarich:open-dialog", to: "#delete_user")
              }
            >{t(@locale, "settings.users.index.delete", %{})}</button>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp status(0), do: "inactive"
  defp status(1), do: "active"
  defp status(2), do: "trial"
  defp badge(0), do: "error"
  defp badge(1), do: "success"
  defp badge(2), do: "warning"
end
