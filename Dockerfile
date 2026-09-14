# Overlay for running casual-review inside Capsule
# (https://github.com/cursorinsight/casual-capsule), via its
# CAPSULE_CUSTOM_COMPOSE extension point. See compose.yml and the
# "Running inside Capsule" section of README.md.
# hadolint ignore=DL3007
FROM casual-capsule-cli:latest

COPY bin /opt/casual-review/bin
COPY lib /opt/casual-review/lib
COPY libexec /opt/casual-review/libexec
COPY prompts /opt/casual-review/prompts
RUN chmod -R a+rX \
      /opt/casual-review/bin \
      /opt/casual-review/lib \
      /opt/casual-review/libexec \
      /opt/casual-review/prompts && \
    chmod 755 \
      /opt/casual-review/bin/casual-review \
      /opt/casual-review/libexec/casual-review/completion \
      /opt/casual-review/libexec/casual-review/review \
      /opt/casual-review/libexec/casual-review/process \
      /opt/casual-review/libexec/casual-review/gerrit/export \
      /opt/casual-review/libexec/casual-review/gerrit/upload \
      /opt/casual-review/libexec/casual-review/gerrit/respond \
      /opt/casual-review/libexec/casual-review/github/upload && \
    ln -sf /opt/casual-review/bin/casual-review \
      /usr/local/bin/casual-review
