CORE := browser/casual-review-upload-core.js
USER_SCRIPT ?= browser/upload-gerrit-reviews.user.js
GERRIT_PLUGIN ?= browser/casual-review-upload.js
LABELS_JSON_NODE := const v=JSON.parse(process.env.GERRIT_LABELS_JSON);
LABELS_JSON_NODE += if(!v||typeof v!=="object"||Array.isArray(v))
LABELS_JSON_NODE += throw new Error("GERRIT_LABELS_JSON must be object");
LABELS_JSON_NODE += process.stdout.write(JSON.stringify(v));
GERRIT_MATCH_NODE := try{const u=new URL(process.env.GERRIT_URL);
GERRIT_MATCH_NODE += const p=u.pathname.replace(/\/+$$/,"");
GERRIT_MATCH_NODE += process.stdout.write(u.origin+p+"/c/*");}catch(e){
GERRIT_MATCH_NODE += console.error("Error: GERRIT_URL must include scheme");
GERRIT_MATCH_NODE += process.exit(1);}

.PHONY: browser-artifacts browser-labels userscript gerrit-plugin
.PHONY: check-browser-artifacts clean check test

browser-artifacts: userscript gerrit-plugin

browser-labels:
	@if [ -z "$${GERRIT_LABELS_JSON:-}" ]; then \
	  printf '%s\n' \
	    'Warning: GERRIT_LABELS_JSON is undefined; browser labels disabled' \
	    >&2; \
	fi

clean:
	@rm -f -- "$(USER_SCRIPT)" "$(GERRIT_PLUGIN)"

check:
	@./tests/check_all.sh

test:
	@./tests/test_all.sh

userscript: browser-labels
	@mkdir -p "$(dir $(USER_SCRIPT))"
	@gerrit_url="$(GERRIT_URL)"; \
	if [ -z "$$gerrit_url" ]; then \
	  if [ -t 0 ]; then \
		printf 'Gerrit URL: ' >&2; \
		IFS= read -r gerrit_url; \
	  else \
		printf '%s\n' 'Error: set GERRIT_URL for userscript' >&2; \
		exit 1; \
	  fi; \
	fi; \
	if [ -z "$$gerrit_url" ]; then \
	  printf '%s\n' 'Error: Gerrit URL must not be empty' >&2; \
	  exit 1; \
	fi; \
	match_url=$$(GERRIT_URL="$$gerrit_url" \
	  node -e '$(GERRIT_MATCH_NODE)') || exit 1; \
	labels_json="$${GERRIT_LABELS_JSON:-}"; \
	if [ -z "$$labels_json" ]; then labels_json='{}'; fi; \
	labels_json=$$(GERRIT_LABELS_JSON="$$labels_json" \
	  node -e '$(LABELS_JSON_NODE)') || exit 1; \
	{ \
	  printf '%s\n' '// ==UserScript=='; \
	  printf '%s\n' '// @name         Casual Review Gerrit Upload'; \
	  printf '%s\n' \
		'// @namespace    https://github.com/cursorinsight/casual-review'; \
	  printf '%s\n' '// @version      0.1.0'; \
	  printf '%s\n' \
		'// @description  Upload casual-review JSON bundles on Gerrit'; \
	  printf '%s\n' "// @match        $${match_url}"; \
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

gerrit-plugin: browser-labels
	@mkdir -p "$(dir $(GERRIT_PLUGIN))"
	@labels_json="$${GERRIT_LABELS_JSON:-}"; \
	if [ -z "$$labels_json" ]; then labels_json='{}'; fi; \
	labels_json=$$(GERRIT_LABELS_JSON="$$labels_json" \
	  node -e '$(LABELS_JSON_NODE)') || exit 1; \
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

check-browser-artifacts:
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
