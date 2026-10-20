import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
const output = fileURLToPath(
  new URL(
    "../../test/fixtures/map_ui/rails-1.16.0-family-rows.json",
    import.meta.url,
  ),
);
const source = execFileSync(
  "git",
  ["show", "1.16.0:app/javascript/controllers/maps/maplibre_controller.js"],
  { encoding: "utf8" },
);
class Element {
  constructor(tag) {
    this.tag = tag;
    this.className = "";
    this.dataset = new Proxy(
      {},
      {
        set(target, key, value) {
          target[key] = String(value);
          return true;
        },
      },
    );
    this.style = {};
    this.children = [];
    this.textContent = "";
  }
  append(...children) {
    this.children.push(...children);
  }
  replaceChildren(...children) {
    this.children = children;
  }
}
const methods = source.slice(
  source.indexOf("  renderFamilyMembersList(locations) {"),
  source.indexOf("  centerOnFamilyMember(event) {"),
);
const controller = vm.runInNewContext(
  `({${methods.replace(/\n  getFamilyMemberColor\(/, ",\n  getFamilyMemberColor(")}})`,
  {
    document: {
      documentElement: { lang: "en" },
      createElement: (tag) => new Element(tag),
    },
    translate: (key) =>
      ({
        "family.none_sharing": "No family members sharing location",
        "common.unknown": "Unknown",
      })[key],
  },
);
const rows = [
  {
    user_id: 7,
    name: "<Member & name>",
    email: "member@example.invalid",
    address: "<Street & City>",
    latitude: 52.4,
    longitude: 13.5,
    updated_at: "2026-06-02T12:34:00Z",
  },
  {
    user_id: 8,
    latitude: 52.4,
    longitude: 13.5,
    email: "other@example.invalid",
    updated_at: "2026-06-02T12:34:00Z",
  },
  {
    user_id: 9,
    latitude: 52.4,
    longitude: 13.5,
    updated_at: "2026-06-02T12:34:00Z",
  },
];
const container = new Element("div");
Object.assign(controller, {
  hasFamilyMembersContainerTarget: true,
  familyMembersContainerTarget: container,
  timezoneValue: "Europe/Berlin",
});
controller.renderFamilyMembersList(rows);
for (const row of container.children) {
  delete row.dataset.action;
  delete row.dataset.memberId;
}
const expected = container.children;
controller.renderFamilyMembersList([]);
writeFileSync(
  output,
  JSON.stringify(
    {
      emptyHtml: container.innerHTML,
      source:
        "1.16.0:app/javascript/controllers/maps/maplibre_controller.js#renderFamilyMembersList",
      rows,
      expected,
    },
    null,
    2,
  ) + "\n",
);
