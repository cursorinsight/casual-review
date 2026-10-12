CORE := browser/casual-review-upload-core.js
USER_SCRIPT ?= browser/upload-gerrit-reviews.user.js
GERRIT_PLUGIN ?= browser/casual-review-upload.js

LABELS_JSON_JQ := if type == "object" then . else
LABELS_JSON_JQ += error("GERRIT_LABELS_JSON must be an object") end

require = $(if $(strip $($(1))),,$(error $(1) is required))

.PHONY: help
help: ## Show this help.
	@awk 'BEGIN {FS = ":.*##[[:space:]]*"} \
	  /^[[:alnum:]_-]+:.*##/ {printf "  %-24s %s\n", $$1, $$2}' \
	  $(MAKEFILE_LIST)

.PHONY: browser-artifacts
browser-artifacts: userscript gerrit-plugin  ## Build browser scripts.

.PHONY: clean
clean: ## Remove generated browser scripts.
	@rm -f -- "$(USER_SCRIPT)" "$(GERRIT_PLUGIN)"

.PHONY: mrproper
mrproper: clean  ## Remove generated scripts, dependencies, and test output.
	@rm -rf -- node_modules playwright/test-results \
	  playwright/playwright-report playwright/.auth

.PHONY: check
check: ## Run linters and static checks.
	@./tests/check_all.sh

.PHONY: test
test: ## Run test suites.
	@./tests/test_all.sh

.PHONY: install-deps
install-deps: ## Install Node.js and Playwright dependencies.
	@npm ci
	@npx playwright install chromium

.PHONY: login
login: ## Save a Gerrit login session for browser tests.
	$(call require,GERRIT_URL)
	@gerrit_url="$(GERRIT_URL)"; \
	mkdir -p playwright/.auth; \
	npx playwright codegen --ignore-https-errors \
	  --save-storage=playwright/.auth/gerrit.json \
	  "$${gerrit_url%/}/login/"

.PHONY: test-gerrit-browser
test-gerrit-browser: ## Run browser tests against Gerrit.
	$(call require,GERRIT_URL)
	$(call require,GERRIT_TEST_PROJECT)
	$(call require,GERRIT_E2E_ALLOW_WRITES)
	@if [ "$(GERRIT_E2E_ALLOW_WRITES)" != 1 ]; then \
	  printf '%s\n' \
		'Error: GERRIT_E2E_ALLOW_WRITES must be 1' >&2; \
	  exit 1; \
	fi
	@npm run test:gerrit-browser

.PHONY: userscript
userscript: browser-labels  ## Generate the Tampermonkey userscript.
	$(call require,GERRIT_URL)
	@mkdir -p "$(dir $(USER_SCRIPT))"
	@labels_json="$${GERRIT_LABELS_JSON:-}"; \
	if [ -z "$$labels_json" ]; then labels_json='{}'; fi; \
	labels_json=$$(printf '%s\n' "$$labels_json" | \
	  jq -ce '$(LABELS_JSON_JQ)') || exit 1; \
	{ \
	  printf '%s\n' '// ==UserScript=='; \
	  printf '%s\n' '// @name         Casual Review Gerrit Upload'; \
	  printf '%s\n' \
		'// @namespace    https://github.com/cursorinsight/casual-review'; \
	  printf '%s\n' '// @version      0.1.0'; \
	  printf '%s\n' \
		'// @description  Upload casual-review JSON bundles on Gerrit'; \
	  printf '%s\n' \
		'// @match        $(patsubst %/,%,$(GERRIT_URL))/c/*'; \
	  printf '%s\n' '// @grant        none'; \
	  printf '%s\n' '// @run-at       document-idle'; \
	  printf '%s\n' '// ==/UserScript=='; \
	  printf '\n'; \
	  sed -n '1,$$p' "$(CORE)"; \
	  printf '\n'; \
	  printf '%s\n' \
		"if (typeof window !== 'undefined' && window.document) {"; \
	  printf '%s\n' '  globalThis.CasualReviewUpload.configure({'; \
	  printf '%s\n' "    labels: $${labels_json},"; \
	  printf '%s\n' '  });'; \
	  printf '%s\n' '  globalThis.CasualReviewUpload.init(globalThis);'; \
	  printf '%s\n' '}'; \
	} >"$(USER_SCRIPT)"

.PHONY: gerrit-plugin
gerrit-plugin: browser-labels  ## Generate the Gerrit plugin.
	@mkdir -p "$(dir $(GERRIT_PLUGIN))"
	@labels_json="$${GERRIT_LABELS_JSON:-}"; \
	if [ -z "$$labels_json" ]; then labels_json='{}'; fi; \
	labels_json=$$(printf '%s\n' "$$labels_json" | \
	  jq -ce '$(LABELS_JSON_JQ)') || exit 1; \
	{ \
	  printf '%s\n' '/* global Gerrit */'; \
	  sed -n '1,$$p' "$(CORE)"; \
	  printf '\n'; \
	  printf '%s\n' '(function casualReviewUploadPlugin(root) {'; \
	  printf '%s\n' "  'use strict';"; \
	  printf '%s\n' \
		"  if (!root.Gerrit || typeof root.Gerrit.install !== 'function') {"; \
	  printf '%s\n' '    return;'; \
	  printf '%s\n' '  }'; \
	  printf '%s\n' '  root.Gerrit.install(() => {'; \
	  printf '%s\n' '    root.CasualReviewUpload.configure({'; \
	  printf '%s\n' "      labels: $${labels_json},"; \
	  printf '%s\n' '    });'; \
	  printf '%s\n' '    root.CasualReviewUpload.init(root);'; \
	  printf '%s\n' '  });'; \
	  printf '%s\n' \
		"})(typeof globalThis !== 'undefined' ? globalThis : this);"; \
	} >"$(GERRIT_PLUGIN)"

.PHONY: check-browser-artifacts
check-browser-artifacts: ## Validate generated browser scripts.
	@tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT INT HUP TERM; \
	gerrit_url="$(GERRIT_URL)"; \
	if [ -z "$$gerrit_url" ]; then \
	  if [ ! -r "$(USER_SCRIPT)" ]; then \
		gerrit_url=https://example.com; \
	  fi; \
	fi; \
	if [ -z "$$gerrit_url" ]; then \
	  gerrit_url=$$(sed -n \
		's#^// @match[[:space:]]*\(.*\)/c/\*#\1#p' \
		"$(USER_SCRIPT)" | sed -n '1p'); \
	fi; \
	if [ -z "$$gerrit_url" ]; then \
	  printf '%s\n' 'Error: set GERRIT_URL for generated check' >&2; \
	  exit 1; \
	fi; \
	$(MAKE) --no-print-directory \
	  USER_SCRIPT="$$tmp/upload-gerrit-reviews.user.js" \
	  GERRIT_PLUGIN="$$tmp/casual-review-upload.js" \
	  GERRIT_URL="$$gerrit_url" browser-artifacts >/dev/null; \
	node --check "$$tmp/upload-gerrit-reviews.user.js" >/dev/null; \
	node --check "$$tmp/casual-review-upload.js" >/dev/null; \
	if [ -r "$(USER_SCRIPT)" ]; then \
	  diff -u "$(USER_SCRIPT)" "$$tmp/upload-gerrit-reviews.user.js"; \
	fi; \
	if [ -r "$(GERRIT_PLUGIN)" ]; then \
	  diff -u "$(GERRIT_PLUGIN)" "$$tmp/casual-review-upload.js"; \
	fi

# -----------------------------------------------------------------------------
# Internal targets
# -----------------------------------------------------------------------------

.PHONY: browser-labels
browser-labels:
	@if [ -z "$${GERRIT_LABELS_JSON:-}" ]; then \
	  printf '%s\n' \
		'Warning: GERRIT_LABELS_JSON is undefined; browser labels disabled' \
		>&2; \
	fi
