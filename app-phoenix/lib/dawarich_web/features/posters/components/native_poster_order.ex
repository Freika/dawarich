defmodule DawarichWeb.NativePosterOrder do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.Icon

  @paper_spec "200 gsm premium matte"
  @sizes ~w(print-30x40 print-50x70 print-70x100)

  attr :locale, :string, required: true

  def poster_order(assigns) do
    assigns = assign(assigns, paper_spec: @paper_spec, sizes: @sizes)

    ~H"""
    <div class="hidden space-y-2" data-poster-order-section>
      <div class="divider my-0 text-xs font-medium opacity-50">{p(@locale, "order_a_print")}</div>

      <div class="space-y-1.5" data-poster-order-cta>
        <button
          type="button"
          class="btn btn-secondary btn-sm h-auto w-full py-1.5"
          data-poster-order-open
        >
          <Icon.icon name="package" class="h-4 w-4 shrink-0" />
          {p(@locale, "order_a_printed_poster")}
        </button>
        <.badges locale={@locale} spec={@paper_spec} />
      </div>

      <div
        class="hidden space-y-2 rounded-lg border border-base-300 bg-base-100 p-3"
        data-poster-size-picker
      >
        <p class="text-sm font-semibold">{p(@locale, "choose_a_print_size")}</p>
        <.badges locale={@locale} spec={@paper_spec} />
        <div class="space-y-1">
          <button
            :for={id <- @sizes}
            type="button"
            class="btn btn-outline btn-sm h-auto w-full flex-wrap justify-between gap-1 py-1.5"
            data-poster-print-size={id}
          >
            <span class="min-w-0">{t(@locale, "javascript.poster.layouts." <> id, %{})}</span>
            <span class="opacity-70" data-poster-print-price></span>
          </button>
        </div>
        <button type="button" class="btn btn-ghost btn-xs w-full" data-poster-size-cancel>
          {p(@locale, "cancel")}
        </button>
      </div>

      <div
        class="hidden space-y-2 rounded-lg border border-base-300 bg-base-100 p-3"
        data-poster-order-dialog
      >
        <p class="text-sm font-semibold [overflow-wrap:anywhere]" data-poster-order-summary></p>
        <.badges locale={@locale} spec={@paper_spec} stripe />
        <p class="text-xs leading-snug opacity-70">
          {p(@locale, "printed_by_gelato_exactly_as_previewed_made_to_order_so")}
        </p>
        <p
          class="hidden text-xs text-error [overflow-wrap:anywhere]"
          role="alert"
          data-poster-order-error
        >
        </p>
        <div class="flex flex-wrap gap-2" data-poster-order-actions>
          <button
            type="button"
            class="btn btn-primary btn-sm h-auto min-w-0 flex-1 py-1.5"
            data-poster-order-confirm
          >
            {p(@locale, "order_this_poster")}
          </button>
          <button type="button" class="btn btn-ghost btn-sm" data-poster-order-back>
            {p(@locale, "back")}
          </button>
        </div>

        <ol class="hidden space-y-3" data-poster-order-steps>
          <.step name="prepare" label={p(@locale, "preparing_poster")} />
          <.step name="upload" label={p(@locale, "uploading_poster")} upload />
          <li class="space-y-1.5 opacity-40" data-poster-order-step="checkout">
            <p class="text-xs font-medium">{p(@locale, "continue_to_order")}</p>
            <a
              class="btn btn-primary btn-sm btn-disabled h-auto w-full py-1.5"
              aria-disabled="true"
              target="_blank"
              rel="noopener"
              data-poster-checkout
            >{p(@locale, "continue_to_payment")}</a>
            <a class="link hidden text-xs" target="_blank" rel="noopener" data-poster-order-page>
              {p(@locale, "checkout_not_working_open_your_order_page")}
            </a>
            <button type="button" class="btn btn-ghost btn-xs hidden w-full" data-poster-order-done>
              {p(@locale, "close")}
            </button>
          </li>
        </ol>
      </div>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :spec, :string, required: true
  attr :stripe, :boolean, default: false

  defp badges(assigns) do
    ~H"""
    <p class="flex flex-wrap items-center gap-x-1.5 gap-y-1 text-xs">
      <span class="badge badge-success badge-outline badge-sm h-auto">{p(@locale, "free_eu_shipping")}</span>
      <span class="badge badge-outline badge-sm h-auto">{@spec}</span>
      <span :if={@stripe} class="opacity-60">{p(@locale, "pay_via_stripe")}</span>
    </p>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :upload, :boolean, default: false

  defp step(assigns) do
    ~H"""
    <li class="space-y-1.5 opacity-40" data-poster-order-step={@name}>
      <p class="flex items-center gap-1.5 text-xs font-medium">
        <span
          class="hidden h-3 w-3 shrink-0 animate-spin rounded-full border-2 border-current border-r-transparent"
          data-role="spinner"
        ></span>
        <span class="hidden text-success" data-role="done">
          <Icon.icon name="circle-check" class="h-3.5 w-3.5" />
        </span>
        <span>{@label}</span>
      </p>
      <progress
        :if={@upload}
        class="progress progress-primary hidden h-1.5 w-full"
        value="0"
        max="100"
        data-role="bar"
        data-poster-upload-bar
      ></progress>
      <progress :if={!@upload} class="progress progress-primary hidden h-1.5 w-full" data-role="bar"></progress>
    </li>
    """
  end

  defp p(locale, key), do: t(locale, "posters.studio." <> key, %{})
end
