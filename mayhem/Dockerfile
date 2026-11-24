# syntax=docker/dockerfile:1.7
# Commit image for Unvanquished (gamelogic for the Daemon engine). Builds the real sgame
# objects with ASan+UBSan via upstream's CMake and links in-process libFuzzer harnesses.
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends \
      cmake ninja-build python3-yaml python3-jinja2 zlib1g-dev nettle-dev libgmp-dev liblua5.4-dev \
      git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# The git submodules the sgame build needs, pinned to the commits this tree's gitlinks record
# (git ls-tree HEAD daemon libs/glm libs/recastnavigation). The CI checkout does not populate
# submodules, so they are fetched here once (SPEC §6.2 item 19) and build.sh points at them offline.
ARG DAEMON_SHA=8c9c5626153996b9c5eb1764fb1807cfd4c23adc
ARG GLM_SHA=cc98465e3508535ba8c7f6208df934c156a018dc
ARG RECAST_SHA=32e5f94b111d40c2a1063cabeff9873c0d95c7ba
RUN set -e; fetch() { d=/opt/toolchains/deps/$1-$3/src; mkdir -p "$d"; git -C "$d" init -q; \
      git -C "$d" fetch -q --depth 1 "https://github.com/$2" "$3"; git -C "$d" checkout -q FETCH_HEAD; \
      test "$(git -C "$d" rev-parse HEAD)" = "$3"; rm -rf "$d/.git"; chmod -R a+rX,go-w "/opt/toolchains/deps/$1-$3"; }; \
    fetch daemon DaemonEngine/Daemon "$DAEMON_SHA"; \
    fetch glm Unvanquished/glm "$GLM_SHA"; \
    fetch recastnavigation Unvanquished/recastnavigation "$RECAST_SHA"
ENV UNV_DAEMON_DIR=/opt/toolchains/deps/daemon-8c9c5626153996b9c5eb1764fb1807cfd4c23adc/src \
    UNV_GLM_DIR=/opt/toolchains/deps/glm-cc98465e3508535ba8c7f6208df934c156a018dc/src \
    UNV_RECAST_DIR=/opt/toolchains/deps/recastnavigation-32e5f94b111d40c2a1063cabeff9873c0d95c7ba/src

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
