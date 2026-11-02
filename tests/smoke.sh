#!/usr/bin/env bash
set -euo pipefail

image="${1:?usage: bash tests/smoke.sh IMAGE PLATFORM}"
platform="${2:?usage: bash tests/smoke.sh IMAGE PLATFORM}"
volume="lardo-smoke-${RANDOM}-$$"
trap 'docker volume rm "$volume" >/dev/null' EXIT
docker volume create "$volume" >/dev/null

run=(docker run --rm --platform "$platform" --network none
  --read-only --cap-drop ALL --security-opt no-new-privileges:true
  --tmpfs /tmp:rw,nosuid,nodev,size=64m,mode=1777
  --mount "type=volume,src=$volume,dst=/data")

"${run[@]}" "$image" --version
"${run[@]}" "$image" --help >/dev/null
# Only fixture credentials are used; the test has no network or Lark account.
if "${run[@]}" "$image" config init --help | grep -- --app-secret-stdin >/dev/null; then
  printf '%s\n' 'smoke-test-secret' | "${run[@]}" -i "$image" \
    config init --app-id cli_smoke_test --app-secret-stdin --brand feishu >/dev/null
else
  # Older releases only accept a flag. This is a public test fixture, not a secret.
  "${run[@]}" "$image" config init --app-id cli_smoke_test \
    --app-secret smoke-test-secret --brand feishu >/dev/null
fi

# A new container must be able to resolve the encrypted secret. The dry run
# requires app configuration, but does not send a request to Lark.
"${run[@]}" "$image" api GET /open-apis/contact/v3/users \
  --as bot --dry-run >/dev/null

"${run[@]}" --entrypoint /bin/sh "$image" -ec '
  test "$(id -u)" = 10001
  test "$HOME" = /data
  test -s "$LARKSUITE_CLI_CONFIG_DIR/config.json"
  test -n "$(find "$LARKSUITE_CLI_DATA_DIR" -name master.key -size +0c -print)"
  test -n "$(find "$LARKSUITE_CLI_DATA_DIR" -name "*.enc" -size +0c -print)"
  ! grep -R -q smoke-test-secret "$LARKSUITE_CLI_CONFIG_DIR"
  test ! -e /data/.agents
  test ! -e /data/.claude
  test ! -e /data/.npm
  ! command -v node
  ! command -v npm
  ! command -v npx
  ! touch /usr/local/bin/unexpected-write 2>/dev/null
'
echo "Smoke test passed: $platform"
