defmodule DawarichWeb.SharingNativeActive do
  @moduledoc false
  use DawarichWeb, :html
  attr :share, :map, required: true
  attr :locale, :string, required: true
  attr :list, :boolean, default: false

  def active(assigns) do
    ~H"""
    <section data-share-id={@share.id} class="space-y-4 min-w-0">
      <h2 :if={!@list} class="text-xl font-bold">{s(@locale, "sharing")}</h2>
      <span class="badge badge-success h-auto">{t(
        @locale,
        if(Dawarich.SharedLinks.FamilyAudience.family_only?(@share),
          do: "shared_links.family.only",
          else: "shared_links.modal_active.public_link"
        ),
        %{}
      )}</span>
      <p>{s(@locale, "view_count", %{count: @share.view_count})}</p>
      <div class="flex flex-wrap gap-2">
        <div
          :for={
            field <-
              if(@share[:protected?] and not Dawarich.SharedLinks.FamilyAudience.family_only?(@share),
                do: ["url", "phrase"],
                else: ["url"]
              )
          }
          id={"sharing-reveal-#{@share.id}-#{field}"}
          phx-hook="SharingReveal"
          data-url={"/native/sharing/#{@share.id}/#{field}"}
          data-copied-label={t(@locale, "javascript.messages.copied_to_clipboard", %{})}
          data-failed-label={
            t(@locale, "javascript.messages.failed_to_copy_please_copy_manually", %{})
          }
          class="min-w-0"
        >
          <button type="button" data-reveal class="btn btn-outline btn-sm h-auto whitespace-normal">{s(
            @locale,
            if(field == "url", do: "copy_link", else: "copy_magic_phrase")
          )}</button>
          <span role="status" aria-live="polite" data-status class="text-sm"></span>
        </div>
        <a
          href={"/s/" <> @share.id}
          target="_blank"
          rel="noopener"
          class="btn btn-outline btn-sm h-auto whitespace-normal"
        >{s(@locale, "open_in_new_tab")}</a>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          :for={
            {action, key} <-
              if(@list,
                do: [{"revoke", "revoke"}],
                else: [
                  {"regenerate", "regenerate_url"},
                  {"regenerate_phrase", "regenerate_phrase"},
                  {"revoke", "revoke"}
                ]
              )
          }
          type="button"
          phx-click="sharing_prepare"
          phx-value-action={action}
          phx-value-id={if @list, do: @share.id}
          class="btn btn-outline btn-sm h-auto whitespace-normal"
        >{s(@locale, key)}</button>
      </div>
    </section>
    """
  end

  defp s(locale, key, attrs \\ %{}), do: t(locale, "shared_links.modal_active." <> key, attrs)
end
