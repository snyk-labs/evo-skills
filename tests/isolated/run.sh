#!/usr/bin/env bash
# Runs the snyk-evo-code-scan skill scripts in fresh, throwaway containers that have
# no Snyk CLI and no Snyk credentials, as a non-root user.
#
# Usage:
#   tests/isolated/run.sh                    # all images
#   tests/isolated/run.sh alpine:3.20        # specific image(s)
#   SNYK_TOKEN=... tests/isolated/run.sh     # also run a real authenticated scan
#
# Requires Docker. Scan results from authenticated runs are copied to tests/isolated/out/<image>/.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
skill="$repo/skills/snyk-evo-code-scan"
fixture="$repo/tests/fixtures/vulnerable-app"

images=("$@")
[ ${#images[@]} -eq 0 ] && images=(ubuntu:24.04 buildpack-deps:bookworm-curl alpine:3.20)

docker_cmd=(docker)
# sudo resets the environment, and `docker run -e VAR` reads VAR from the client's environment.
docker info >/dev/null 2>&1 || docker_cmd=(sudo --preserve-env=SNYK_TOKEN,SNYK_API docker)

overall=0
for image in "${images[@]}"; do
  echo
  echo "################ $image ################"
  out_dir="$here/out/${image//[:\/]/_}"
  mkdir -p "$out_dir"
  chmod 777 "$out_dir"

  # Minimal images may ship without curl/wget or CA certificates; an agent would install them
  # with the system package manager, so the bootstrap tries the same before dropping root.
  # shellcheck disable=SC2016
  bootstrap='
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
      { apt-get update -qq && apt-get install -y -qq curl ca-certificates; } >/dev/null 2>&1 \
        || echo "bootstrap: could not install curl (package mirror unreachable?)"
    fi
    if command -v useradd >/dev/null 2>&1; then useradd -m agent; else adduser -D agent; fi
    exec su agent -s /bin/sh -c "cd ~ && SNYK_TOKEN=\"\$SNYK_TOKEN\" RESULTS_OUT=/out sh /tests/container-test.sh"
  '

  env_args=()
  if [ -n "${SNYK_TOKEN:-}" ]; then
    env_args=(-e SNYK_TOKEN)
  else
    env_args=(-e SNYK_TOKEN=)
  fi
  [ -n "${SNYK_API:-}" ] && env_args+=(-e SNYK_API)

  if "${docker_cmd[@]}" run --rm \
      "${env_args[@]}" \
      -v "$skill:/skill:ro" \
      -v "$fixture:/fixture:ro" \
      -v "$here:/tests:ro" \
      -v "$out_dir:/out" \
      "$image" sh -c "$bootstrap"; then
    echo "==> $image: OK"
  else
    echo "==> $image: FAILED"
    overall=1
  fi
done

exit $overall
