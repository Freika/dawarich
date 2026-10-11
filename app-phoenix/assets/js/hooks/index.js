import { AchievementUnlocks } from "./achievement_unlocks.js"
import { ArchiveChecksum } from "./archive_checksum.js"
import { AreaPreview } from "./area_preview.js"
import { ChangelogWidget } from "./changelog_widget.js"
import { Clipboard } from "./clipboard.js"
import { Dismissible } from "./dismissible.js"
import { EmojiPicker } from "./emoji_picker.js"
import { FamilyHook } from "./family.js"
import { MapHook } from "./map.js"
import { MapMatchingDemo } from "./map_matching_demo.js"
import { MapPreview } from "./map_preview.js"
import { OnboardingHook } from "./onboarding.js"
import { PosterStudio } from "./poster_studio.js"
import { PublicMap } from "./public_map.js"
import { ScrollIntoView } from "./scroll_into_view.js"
import { TripHook } from "./trip.js"
import { VideoStudio } from "./video_studio.js"

export const hooks = {
  AchievementUnlocks,
  ArchiveChecksum,
  AreaPreview,
  ChangelogWidget,
  Clipboard,
  Dismissible,
  EmojiPicker,
  Map: MapHook,
  Onboarding: OnboardingHook,
  MapPreview,
  PublicMap,
  PosterStudio,
  VideoStudio,
  Family: FamilyHook,
  Trip: TripHook,
  MapMatchingDemo,
  ScrollIntoView,
}
