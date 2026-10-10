# Phoenix runtime file paths

`config/shared_link_wordlist.txt` is the canonical shared-link wordlist for Rails
and Phoenix. Phoenix embeds its words when compiling `ShareManagement.Read` and
tracks the source as an external resource so edits trigger recompilation.
Local compilation reads the repository file using a path anchored to the module.
The Docker builder copies that same file into Phoenix's `priv` before `mix release`;
compilation uses the staged file when the repository config tree is absent.
Phrase generation needs neither a runtime file, a Rails root, nor a specific cwd.
Do not maintain a separate Phoenix wordlist.

Files shared with the application tree use `Dawarich.RailsRoot.root()`:
explicit `:rails_root` configuration, then `APP_PATH`, then the repository root
anchored at compilation for local development. The image sets `APP_PATH=/var/app`.
External releases must set `APP_PATH` to their application data and build-input tree
when serving those resources; mutable storage and local configuration stay there.
Explicit paths such as `:i18n_path`, `:achievements_path`, `:app_version_file`, and
`:public_root` keep their precedence.

The shared root covers translations, achievements, asset manifests and importmaps,
version reads, public files and error pages, icons, API docs, poster themes and
renderer paths, storage configuration, and the development-only local secret file.
Build tasks use the same root and anchor their own source glob to the module.
Existing module-relative `priv` inputs are already compiled or release-relative;
caller-supplied import/export paths do not derive their root from cwd.

Regression coverage is in `phrase_release_test.exs` and `rails_root_test.exs`.
Both run their reads from an unrelated directory with `:rails_root` unset.
