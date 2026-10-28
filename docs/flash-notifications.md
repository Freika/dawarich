# Flash notifications

Related issue: [#3765 — Mass errors - no way to clear](https://github.com/Freika/dawarich/issues/3765).

Shared knowledge base: `Dawarich — Flash notification dismissal (#3765)`
(AFFiNE document ID `jTUggz7IO4k4ZxRf9AgQc`).

The shared flash container offers **Close all notifications** when at least two
messages are present. It clears the current messages together, including a mix of
server-rendered, Turbo-appended and JavaScript-generated flashes. A single message
keeps its individual close button. Errors remain visible until dismissed;
`notice` and `success` still expire after five seconds.

Notifications share a compact neutral panel, with semantic status icons and
subtle row separators instead of full-color alert backgrounds. Text stays
left-aligned, long filenames wrap, and each close button has a 44px touch target
on the right. The panel follows the existing light and dark theme tokens.

The list scrolls within a 32rem height limit, or the available viewport height on
smaller screens. The bulk button stays in an opaque toolbar at the top, above the
messages, so it remains reachable when a large import produces many errors. The
empty container stays available for later messages on the same page.

## Implementation

- `app/views/shared/_flash.html.erb` owns the `flash` Stimulus controller and the
  translated bulk button. Translations live in `config/locales/flash.*.yml`.
- Both `shared/_flash_message.html.erb` and `Flash.show` mark each message with
  `data-flash-target="message"`. Keep this attribute on any new flash renderer.
- Stimulus target lifecycle callbacks update button visibility after additions,
  individual dismissal and automatic expiration. Declarative actions avoid
  additional event listeners or custom mutation observers across Turbo visits.
- `Flash.show` and `removals` retain their existing individual dismissal and
  timeout behavior. The bulk action removes only message targets.
- `app/assets/stylesheets/flash_notifications.css` defines the panel, message
  layout and theme-aware status colors for both renderers. These styles are
  scoped to flash components; other DaisyUI alerts keep their existing look.

## Verification

Automated checks:

```sh
npm test
bundle exec rspec spec/views/shared/_flash.html.erb_spec.rb
```

Use the project's Ruby activation and an isolated test database when running
Rails checks locally. The view specs cover translated labels in every supported
locale, server-rendered message targets and unchanged timeout values. JavaScript
tests cover the visibility threshold, removal, reuse and reconnection.

Browser regression checklist:

1. On `/imports/new`, select many synthetic GPX files and simulate failed direct
   uploads. Each file error and the final failure summary remain readable.
2. Confirm errors survive longer than five seconds; close one individually, then
   clear the rest with the bulk button using both mouse and keyboard.
3. At mobile width, scroll to the end of the list and confirm the bulk button is
   visible and clickable above the messages.
4. Add a single message after clearing. Its individual close button still works,
   and the bulk button stays hidden.
5. Add success and notice messages, then let them expire. Append server-style
   flashes through Turbo and confirm that visibility follows the message count.
6. Disconnect/reconnect the container repeatedly; one click must invoke the bulk
   action once.
7. Check light and dark themes, all four status icons, long filenames and 320px
   screens. Text must stay readable and close buttons must remain on the right.
