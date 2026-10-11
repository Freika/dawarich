defmodule DawarichWeb.PosterStudioActions do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.Icon

  @paper_spec "200 gsm premium matte"

  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, required: true

  def poster_actions(assigns) do
    assigns = assign(assigns, :paper_spec, @paper_spec)

    ~H"""
    <div class="space-y-2 border-t border-base-content/10 p-3">
      <div class="text-xs opacity-70 space-y-0.5" data-poster-studio-editor-target="summary"></div>

      <div class="divider my-0 text-xs font-medium opacity-50">{p(@locale, "export_a_file")}</div>
      <div class="grid grid-cols-2 gap-2">
        <label class="form-control">
          <span class="label-text text-xs">{p(@locale, "format")}</span>
          <select
            class="select select-bordered select-sm py-0"
            data-poster-studio-editor-target="format"
            data-action="change->poster-studio-editor#updateSummary"
          >
            <option value="png" selected>{p(@locale, "png")}</option>
            <option value="pdf">{p(@locale, "pdf")}</option>
          </select>
        </label>
        <label class="form-control" data-poster-studio-editor-target="dpiField">
          <span class="label-text text-xs">{p(@locale, "print_dpi")}</span>
          <select
            class="select select-bordered select-sm py-0"
            data-poster-studio-editor-target="dpi"
            data-action="change->poster-studio-editor#updateSummary"
          >
            <option value="150">150</option>
            <option value="300" selected>300</option>
          </select>
        </label>
      </div>
      <button
        type="button"
        class="btn btn-primary btn-sm w-full"
        data-poster-studio-editor-target="downloadButton"
        data-action="poster-studio-editor#download"
      >
        <Icon.icon name="download" class="h-4 w-4" />
        {p(@locale, "download")}
      </button>
      <button
        type="button"
        class="btn btn-ghost btn-xs w-full gap-1 opacity-70"
        data-poster-studio-editor-target="saveButton"
        data-action="poster-studio-editor#saveToGallery"
        title={p(@locale, "render_this_area_server_side_as_the_classic_3_4")}
      >
        <Icon.icon name="camera" class="h-3.5 w-3.5" />
        {p(@locale, "save_to_gallery")}
      </button>
      <p class="text-xs text-warning hidden" data-poster-studio-editor-target="saveNotice"></p>

      <div class="hidden space-y-2" data-poster-studio-editor-target="orderSection">
        <div class="divider my-0 text-xs font-medium opacity-50">{p(@locale, "order_a_print")}</div>

        <div class="space-y-1.5" data-poster-studio-editor-target="orderCta">
          <button
            type="button"
            class="btn btn-secondary btn-sm w-full"
            data-poster-studio-editor-target="orderButton"
            data-action="poster-studio-editor#openOrder"
          >
            <Icon.icon name="package" class="h-4 w-4" />
            {p(@locale, "order_a_printed_poster")}
          </button>
          <p class="text-xs flex flex-wrap items-center gap-x-2 gap-y-1">
            <span class="badge badge-success badge-outline badge-sm">{p(@locale, "free_eu_shipping")}</span>
            <span class="badge badge-outline badge-sm">{@paper_spec}</span>
          </p>
        </div>

        <div
          class="hidden rounded-lg border border-base-300 bg-base-100 p-3 space-y-2"
          data-poster-studio-editor-target="sizePicker"
        >
          <p class="text-sm font-semibold">{p(@locale, "choose_a_print_size")}</p>
          <p class="text-xs flex flex-wrap items-center gap-x-1.5 gap-y-1">
            <span class="badge badge-success badge-outline badge-sm">{p(@locale, "free_eu_shipping")}</span>
            <span class="badge badge-outline badge-sm">{@paper_spec}</span>
          </p>
          <div class="space-y-1" data-poster-studio-editor-target="sizePickerOptions"></div>
          <button
            type="button"
            class="btn btn-ghost btn-xs w-full"
            data-action="poster-studio-editor#closeSizePicker"
          >{p(@locale, "cancel")}</button>
        </div>

        <div
          class="hidden rounded-lg border border-base-300 bg-base-100 p-3 space-y-2"
          data-poster-studio-editor-target="orderDialog"
        >
          <p class="text-sm font-semibold" data-poster-studio-editor-target="orderSummary"></p>
          <p class="text-xs flex flex-wrap items-center gap-x-1.5 gap-y-1">
            <span class="badge badge-success badge-outline badge-sm">{p(@locale, "free_eu_shipping")}</span>
            <span class="badge badge-outline badge-sm">{@paper_spec}</span>
            <span class="opacity-60">{p(@locale, "pay_via_stripe")}</span>
          </p>
          <p class="text-xs opacity-70 leading-snug">
            {p(@locale, "printed_by_gelato_exactly_as_previewed_made_to_order_so")}
          </p>
          <p class="text-xs text-error hidden" data-poster-studio-editor-target="orderError"></p>
          <div class="flex gap-2" data-poster-studio-editor-target="orderActions">
            <button
              type="button"
              class="btn btn-primary btn-sm flex-1"
              data-action="poster-studio-editor#confirmOrder"
            >
              {p(@locale, "order_this_poster")}
            </button>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              data-action="poster-studio-editor#openSizePicker"
            >
              {p(@locale, "back")}
            </button>
          </div>

          <ol class="hidden space-y-3" data-poster-studio-editor-target="orderSteps">
            <li
              class="space-y-1.5 opacity-40"
              data-poster-studio-editor-target="orderStep"
              data-step="prepare"
            >
              <p class="flex items-center gap-1.5 text-xs font-medium">
                <span
                  class="hidden h-3 w-3 shrink-0 animate-spin rounded-full border-2 border-current border-r-transparent"
                  data-role="spinner"
                ></span>
                <span class="hidden text-success" data-role="done"><Icon.icon
                  name="circle-check"
                  class="h-3.5 w-3.5"
                /></span>
                <span>{p(@locale, "preparing_poster")}</span>
              </p>
              <progress class="progress progress-primary hidden h-1.5 w-full" data-role="bar"></progress>
            </li>
            <li
              class="space-y-1.5 opacity-40"
              data-poster-studio-editor-target="orderStep"
              data-step="upload"
            >
              <p class="flex items-center gap-1.5 text-xs font-medium">
                <span
                  class="hidden h-3 w-3 shrink-0 animate-spin rounded-full border-2 border-current border-r-transparent"
                  data-role="spinner"
                ></span>
                <span class="hidden text-success" data-role="done"><Icon.icon
                  name="circle-check"
                  class="h-3.5 w-3.5"
                /></span>
                <span>{p(@locale, "uploading_poster")}</span>
              </p>
              <progress
                class="progress progress-primary hidden h-1.5 w-full"
                value="0"
                max="100"
                data-role="bar"
                data-poster-studio-editor-target="uploadBar"
              ></progress>
            </li>
            <li
              class="space-y-1.5 opacity-40"
              data-poster-studio-editor-target="orderStep"
              data-step="checkout"
            >
              <p class="text-xs font-medium">{p(@locale, "continue_to_order")}</p>
              <a
                class="btn btn-primary btn-sm btn-disabled w-full"
                aria-disabled="true"
                target="_blank"
                rel="noopener"
                data-poster-studio-editor-target="checkoutLink"
              >{p(@locale, "continue_to_payment")}</a>
              <a
                class="link hidden text-xs"
                target="_blank"
                rel="noopener"
                data-poster-studio-editor-target="orderPageLink"
              >{p(@locale, "checkout_not_working_open_your_order_page")}</a>
              <button
                type="button"
                class="btn btn-ghost btn-xs hidden w-full"
                data-poster-studio-editor-target="orderDoneButton"
                data-action="poster-studio-editor#closeOrder"
              >{p(@locale, "close")}</button>
            </li>
          </ol>
        </div>
      </div>

      <p class="text-xs opacity-70" data-poster-studio-editor-target="status"></p>

      <turbo-cable-stream-source
        channel="Turbo::StreamsChannel"
        signed-stream-name={@page.posters_stream}
      >
      </turbo-cable-stream-source>
      <form
        class="hidden"
        data-poster-studio-editor-target="saveForm"
        action="/posters"
        accept-charset="UTF-8"
        method="post"
      >
        <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
        <input
          data-poster-studio-editor-target="saveName"
          type="hidden"
          name="poster[name]"
          id="poster_name"
        />
        <input
          data-poster-studio-editor-target="saveTitle"
          type="hidden"
          name="poster[title]"
          id="poster_title"
        />
        <input
          data-poster-studio-editor-target="saveTheme"
          type="hidden"
          name="poster[theme]"
          id="poster_theme"
        />
        <input
          data-poster-studio-editor-target="saveLat"
          type="hidden"
          name="poster[lat]"
          id="poster_lat"
        />
        <input
          data-poster-studio-editor-target="saveLon"
          type="hidden"
          name="poster[lon]"
          id="poster_lon"
        />
        <input
          data-poster-studio-editor-target="saveDistance"
          type="hidden"
          name="poster[distance]"
          id="poster_distance"
        />
        <input
          data-poster-studio-editor-target="saveStartAt"
          type="hidden"
          name="poster[start_at]"
          id="poster_start_at"
        />
        <input
          data-poster-studio-editor-target="saveEndAt"
          type="hidden"
          name="poster[end_at]"
          id="poster_end_at"
        />
        <input
          data-poster-studio-editor-target="saveSource"
          type="hidden"
          name="poster[source]"
          id="poster_source"
        />
        <input
          data-poster-studio-editor-target="saveOpacity"
          type="hidden"
          name="poster[route_opacity]"
          id="poster_route_opacity"
        />
        <input
          data-poster-studio-editor-target="saveWidth"
          type="hidden"
          name="poster[route_width]"
          id="poster_route_width"
        />
      </form>
    </div>
    """
  end

  defp p(locale, key), do: t(locale, "posters.studio." <> key, %{})
end
