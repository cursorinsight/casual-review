# Overlay for running review-commits inside Capsule
# (https://github.com/cursorinsight/casual-capsule), via its
# CAPSULE_CUSTOM_COMPOSE extension point. See compose.yml and the
# "Running inside Capsule" section of README.md.
FROM casual-capsule-cli:latest

COPY bin /opt/multi-cli-gerrit-review/bin
COPY prompts /opt/multi-cli-gerrit-review/prompts
RUN ln -sf /opt/multi-cli-gerrit-review/bin/review-commits \
      /usr/local/bin/review-commits
