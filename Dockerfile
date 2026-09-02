# Overlay for running review-commits inside Capsule
# (https://github.com/cursorinsight/casual-capsule), via its
# CAPSULE_CUSTOM_COMPOSE extension point. See compose.yml and the
# "Running inside Capsule" section of README.md.
# hadolint ignore=DL3007
FROM casual-capsule-cli:latest

COPY bin /opt/casual-review/bin
COPY prompts /opt/casual-review/prompts
RUN chmod -R a+rX \
      /opt/casual-review/bin \
      /opt/casual-review/prompts && \
    chmod 755 \
      /opt/casual-review/bin/review-commits \
      /opt/casual-review/bin/process-reviews \
      /opt/casual-review/bin/export-gerrit-reviews \
      /opt/casual-review/bin/upload-gerrit-reviews \
      /opt/casual-review/bin/respond-gerrit-reviews && \
    for script in review-commits process-reviews \
      export-gerrit-reviews upload-gerrit-reviews \
      respond-gerrit-reviews; do \
      ln -sf "/opt/casual-review/bin/${script}" \
        "/usr/local/bin/${script}"; \
    done
