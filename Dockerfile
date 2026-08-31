# Overlay for running review-commits inside Capsule
# (https://github.com/cursorinsight/casual-capsule), via its
# CAPSULE_CUSTOM_COMPOSE extension point. See compose.yml and the
# "Running inside Capsule" section of README.md.
# hadolint ignore=DL3007
FROM casual-capsule-cli:latest

COPY bin /opt/multi-cli-gerrit-review/bin
COPY prompts /opt/multi-cli-gerrit-review/prompts
RUN chmod -R a+rX /opt/multi-cli-gerrit-review/bin \
      /opt/multi-cli-gerrit-review/prompts && \
    chmod 755 /opt/multi-cli-gerrit-review/bin/review-commits \
      /opt/multi-cli-gerrit-review/bin/process-reviews \
      /opt/multi-cli-gerrit-review/bin/export-gerrit-reviews \
      /opt/multi-cli-gerrit-review/bin/upload-gerrit-reviews \
      /opt/multi-cli-gerrit-review/bin/respond-gerrit-reviews && \
    for script in review-commits process-reviews \
      export-gerrit-reviews upload-gerrit-reviews \
      respond-gerrit-reviews; do \
      ln -sf "/opt/multi-cli-gerrit-review/bin/${script}" \
        "/usr/local/bin/${script}"; \
    done
