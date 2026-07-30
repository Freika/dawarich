# Dreistufiger Entwicklungs- und Deployment-Workflow für Dawarich.
# Alle Ruby- und RSpec-Befehle laufen ausschließlich im DevContainer.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

REPO_DIR := /root/dawarich-immich-tags-dev
DEV_COMPOSE := $(REPO_DIR)/.devcontainer/docker-compose.yml
DEV_SERVICE := dawarich_dev
DEV_CONTAINER := dawarich_dev
DEV_DB_CONTAINER := dawarich_dev_db
DEV_REDIS_CONTAINER := dawarich_dev_redis
TEST_DIR := /root/dawarich-test
TEST_COMPOSE := $(TEST_DIR)/docker-compose.yml
PROD_DIR := /root/dawarich
PROD_COMPOSE := $(PROD_DIR)/docker-compose.yml
IMAGE := dawarich-immich-tags:test
APP_SERVICES := dawarich_app dawarich_sidekiq
FORK_REMOTE := origin
FORK_URL_SUFFIX := cleniemeyer-collab/dawarich.git

RSPEC_FILES := \
		spec/services/immich/shared_links_spec.rb \
		spec/services/photos/search_spec.rb \
		spec/services/shared_links/photo_album_spec.rb \
		spec/services/shared_links/photo_sources_spec.rb \
		spec/services/shared_links/trip_photos_spec.rb \
		spec/requests/api/v1/shared/photos_spec.rb \
		spec/requests/share_links/timelines_spec.rb \
		spec/requests/shared/links_spec.rb

export MESSAGE
export CONFIRM

.PHONY: help status diff devcontainer testvscode review testdawarich commit push dawarich

help: ## Zeigt alle verfügbaren Targets.
	@printf '%s\n' \
		'make help                         Verfügbare Targets anzeigen' \
		'make status                       Git-Status, Branch und Commit anzeigen' \
		'make diff                         Arbeits- und Staging-Diff anzeigen' \
		'make testvscode                   Relevante Specs im laufenden DevContainer ausführen' \
		'make review                       Pflichtprüfung von Diff, Repository-Hygiene und Tests' \
		'make testdawarich                 Testen, Testimage bauen und Testinstanz aktualisieren' \
		'make commit MESSAGE="..."         Sichere Projektänderungen lokal committen' \
		'make push                         Aktuellen Branch ausschließlich zum Fork pushen' \
		'make dawarich CONFIRM=PRODUCTION  Produktionsumgebung nach Tests aktualisieren'

status: ## Zeigt den aktuellen Repository-Zustand.
	@git -C "$(REPO_DIR)" status --short
	@printf 'Branch: '
	@git -C "$(REPO_DIR)" branch --show-current
	@printf 'Commit: '
	@git -C "$(REPO_DIR)" rev-parse --short HEAD

diff: ## Zeigt nicht gestagte und gestagte Änderungen ohne Pager.
	@GIT_PAGER=cat git -C "$(REPO_DIR)" --no-pager diff
	@GIT_PAGER=cat git -C "$(REPO_DIR)" --no-pager diff --staged

devcontainer: ## Startet bei Bedarf den vorhandenen DevContainer samt Dev-Diensten.
	@if docker inspect -f '{{.State.Running}}' "$(DEV_CONTAINER)" 2>/dev/null | grep -qx true; then \
		printf 'DevContainer %s läuft bereits und wird unverändert verwendet.\n' "$(DEV_CONTAINER)"; \
	else \
		printf 'DevContainer läuft nicht; vorhandene Dev-Compose-Services werden gestartet.\n'; \
	if ! docker image inspect devcontainer-dawarich_dev >/dev/null 2>&1; then \
		printf 'Build: docker compose -f %s build %s\n' "$(DEV_COMPOSE)" "$(DEV_SERVICE)"; \
		docker compose -f "$(DEV_COMPOSE)" build "$(DEV_SERVICE)"; \
	fi; \
	for container in "$(DEV_DB_CONTAINER)" "$(DEV_REDIS_CONTAINER)" "$(DEV_CONTAINER)"; do \
		if docker inspect "$$container" >/dev/null 2>&1; then \
			docker start "$$container" >/dev/null; \
		fi; \
	done; \
	if ! docker inspect "$(DEV_DB_CONTAINER)" >/dev/null 2>&1; then \
		printf 'Start: docker compose -f %s run -d --no-deps --name %s -e POSTGRES_DB=dawarich_test dawarich_db\n' \
			"$(DEV_COMPOSE)" "$(DEV_DB_CONTAINER)"; \
		docker compose -f "$(DEV_COMPOSE)" run -d --no-deps \
			--name "$(DEV_DB_CONTAINER)" \
			-e POSTGRES_DB=dawarich_test \
			dawarich_db; \
	fi; \
	if ! docker inspect "$(DEV_REDIS_CONTAINER)" >/dev/null 2>&1; then \
		printf 'Start: docker compose -f %s run -d --no-deps --name %s dawarich_redis\n' \
			"$(DEV_COMPOSE)" "$(DEV_REDIS_CONTAINER)"; \
		docker compose -f "$(DEV_COMPOSE)" run -d --no-deps \
			--name "$(DEV_REDIS_CONTAINER)" \
			dawarich_redis; \
	fi; \
	for attempt in $$(seq 1 60); do \
		if docker exec "$(DEV_DB_CONTAINER)" pg_isready -U postgres -d dawarich_test >/dev/null 2>&1; then \
			break; \
		fi; \
		if [[ "$$attempt" -eq 60 ]]; then \
			printf 'Fehler: Dev-Datenbank wurde nicht rechtzeitig bereit.\n' >&2; \
			exit 1; \
		fi; \
		sleep 1; \
	done; \
	if ! docker inspect "$(DEV_CONTAINER)" >/dev/null 2>&1; then \
		printf 'Start: docker compose -f %s run -d --no-deps --name %s ... %s sleep infinity\n' \
			"$(DEV_COMPOSE)" "$(DEV_CONTAINER)" "$(DEV_SERVICE)"; \
		docker compose -f "$(DEV_COMPOSE)" run -d --no-deps \
			--name "$(DEV_CONTAINER)" \
			-e RAILS_ENV=test \
			-e DATABASE_HOST="$(DEV_DB_CONTAINER)" \
			-e DATABASE_NAME=dawarich_test \
			-e REDIS_URL="redis://$(DEV_REDIS_CONTAINER):6379" \
			"$(DEV_SERVICE)" \
			sleep infinity; \
	fi; \
	fi; \
	docker exec "$(DEV_CONTAINER)" sh -lc 'bundle check || bundle install --jobs 4 --retry 3'; \
	printf 'DevContainer %s ist bereit.\n' "$(DEV_CONTAINER)"

testvscode: devcontainer ## Führt die relevanten RSpec-Tests im DevContainer aus.
	@command='docker exec $(DEV_CONTAINER) sh -lc "bundle exec rails db:test:prepare && bundle exec rspec $(RSPEC_FILES)"'; \
	printf 'Verwendeter Testbefehl:\n%s\n' "$$command"; \
	docker exec "$(DEV_CONTAINER)" \
		sh -lc "bundle exec rails db:test:prepare && bundle exec rspec $(RSPEC_FILES)"

review: ## Prüft den vollständigen Diff, Repository-Hygiene und die relevanten Tests.
	@printf '\n%s\n' '===== VERPFLICHTENDE TECHNISCHE PRÜFUNG ====='
	@git -C "$(REPO_DIR)" status --short
	@git -C "$(REPO_DIR)" diff --check
	@git -C "$(REPO_DIR)" diff --cached --check
	@failed=0; \
	mapfile -d '' -t changed_files < <( \
		{ \
			git -C "$(REPO_DIR)" diff --name-only -z --diff-filter=ACMR; \
			git -C "$(REPO_DIR)" diff --cached --name-only -z --diff-filter=ACMR; \
			git -C "$(REPO_DIR)" ls-files --others --exclude-standard -z; \
		} | sort -zu \
	); \
	for path in "$${changed_files[@]}"; do \
		case "$$path" in \
			.env|.env.*|*/.env|*/.env.*|*.bak|*.tmp|*.swp|*.orig|*.rej|*~|*.log|*.sqlite|*.sqlite3|*.sqlite3-shm|*.sqlite3-wal|log/*|tmp/*|storage/*|coverage/*|config/master.key|config/credentials/*.key) \
				printf 'Fehler: Unerwünschte Datei in den Änderungen: %s\n' "$$path" >&2; \
				failed=1 ;; \
		esac; \
	done; \
	[[ "$$failed" -eq 0 ]]
	@failed=0; \
	mapfile -d '' -t repository_files < <( \
		{ \
			git -C "$(REPO_DIR)" ls-files -z; \
			git -C "$(REPO_DIR)" ls-files --others --exclude-standard -z; \
		} \
	); \
	for path in "$${repository_files[@]}"; do \
		file="$(REPO_DIR)/$$path"; \
		if [[ -f "$$file" ]] && grep -Iq . "$$file"; then \
			if grep -nHE '^(<<<<<<<( .*)?|=======|>>>>>>>( .*)?)$$' "$$file"; then \
				failed=1; \
			fi; \
		fi; \
	done; \
	if [[ "$$failed" -ne 0 ]]; then \
		printf 'Fehler: Nicht aufgelöste Merge-Konfliktmarker gefunden.\n' >&2; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory testvscode
	@printf '%s\n\n' '===== REVIEW ERFOLGREICH: ALLE PRÜFUNGEN BESTANDEN ====='

testdawarich: review ## Prüft, baut das Testimage und aktualisiert nur die Testinstanz.
	@cd "$(REPO_DIR)"; \
	docker build -f docker/Dockerfile -t "$(IMAGE)" .
	@cd "$(TEST_DIR)"; \
	docker compose -f "$(TEST_COMPOSE)" up -d --no-deps --force-recreate $(APP_SERVICES); \
	docker compose -f "$(TEST_COMPOSE)" ps; \
	printf '\nTestinstanz aktualisiert.\nProduktionsumgebung unverändert.\n'

commit: ## Erstellt einen lokalen Commit ohne Push.
	@message="$${MESSAGE:-}"; \
	if [[ -z "$$message" ]]; then \
		printf 'Fehler: MESSAGE fehlt. Aufruf: make commit MESSAGE="..."\n' >&2; \
		exit 1; \
	fi; \
	test "$$(git -C "$(REPO_DIR)" rev-parse --show-toplevel)" = "$(REPO_DIR)"; \
	git -C "$(REPO_DIR)" status --short; \
	git -C "$(REPO_DIR)" add -A -- .; \
	while IFS= read -r path; do \
		case "$$path" in \
			.env|.env.*|*/.env|*/.env.*|log/*|tmp/*|storage/*|coverage/*|*.log|*.sqlite3|*.sqlite3-shm|*.sqlite3-wal|*.bak|*.tmp|*.swp|*~|config/master.key|config/credentials/*.key) \
				printf 'Fehler: Nicht zulässige Datei ist gestagt: %s\n' "$$path" >&2; \
				exit 1 ;; \
		esac; \
	done < <(git -C "$(REPO_DIR)" diff --cached --name-only); \
	if git -C "$(REPO_DIR)" diff --cached --quiet; then \
		printf 'Fehler: Keine zulässigen Projektänderungen zum Committen.\n' >&2; \
		exit 1; \
	fi; \
	git -C "$(REPO_DIR)" commit -m "$$message"

push: ## Pusht den aktuellen Branch ohne Force ausschließlich zum Fork.
	@branch="$$(git -C "$(REPO_DIR)" branch --show-current)"; \
	target="$$(git -C "$(REPO_DIR)" remote get-url --push "$(FORK_REMOTE)")"; \
	if [[ -z "$$branch" ]]; then \
		printf 'Fehler: Detached HEAD kann nicht gepusht werden.\n' >&2; \
		exit 1; \
	fi; \
	case "$$target" in \
		*"$(FORK_URL_SUFFIX)") ;; \
		*) printf 'Fehler: %s ist nicht der erwartete Fork: %s\n' "$(FORK_REMOTE)" "$$target" >&2; exit 1 ;; \
	esac; \
	printf 'Branch: %s\nPush-Ziel: %s (%s)\n' "$$branch" "$(FORK_REMOTE)" "$$target"; \
	git -C "$(REPO_DIR)" push "$(FORK_REMOTE)" "$$branch"

dawarich: review ## Aktualisiert nach Prüfung und Bestätigung ausschließlich das Produktionssystem.
	@if [[ "$${CONFIRM:-}" != "PRODUCTION" ]]; then \
		printf 'Fehler: Produktion nur mit CONFIRM=PRODUCTION aktualisieren.\n' >&2; \
		exit 1; \
	fi; \
	branch="$$(git -C "$(REPO_DIR)" branch --show-current)"; \
	commit="$$(git -C "$(REPO_DIR)" rev-parse --short HEAD)"; \
	printf 'Branch: %s\nCommit: %s\n' "$$branch" "$$commit"; \
	if [[ -n "$$(git -C "$(REPO_DIR)" status --porcelain)" ]]; then \
		printf 'Fehler: Das Git-Repository ist nicht sauber. Produktion bleibt unverändert.\n' >&2; \
		exit 1; \
	fi; \
	cd "$(REPO_DIR)"; \
	docker build -f docker/Dockerfile -t "$(IMAGE)" .; \
	cd "$(PROD_DIR)"; \
	docker compose -f "$(PROD_COMPOSE)" up -d --no-deps --force-recreate $(APP_SERVICES); \
	docker compose -f "$(PROD_COMPOSE)" ps; \
	printf '\nProduktionssystem erfolgreich aktualisiert.\n'
