defmodule DawarichWeb.ShareLinkActive do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]

  embed_templates "share_link_active/*"

  defp s(ctx, key, bindings \\ %{}),
    do: t(ctx.locale, "shared_links.modal_active." <> key, bindings)

  defp url(ctx, share), do: ctx.base_url <> "/s/" <> share.id

  def action(assigns) do
    ~H"""
    <form data-turbo-frame="share-link-modal" class="button_to" method="post" action={@path}>
      <input :if={@method != "post"} type="hidden" name="_method" value={@method} />
      <button class={@class} data-turbo-confirm={s(@ctx, @confirm)} type="submit">
        <.icon name={@icon} class="w-4 h-4" /> {s(@ctx, @label)}
      </button>
      <input type="hidden" name="authenticity_token" value={@ctx.csrf} />
    </form>
    """
  end
end
