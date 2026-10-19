#!/bin/bash
set -euo pipefail
umask 077
for name in APPLE_TEAM_ID APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID MATCH_GIT_URL APP_STORE_CONNECT_PRIVATE_KEY SIGNING_GIT_TOKEN MATCH_PASSWORD; do
  if [ -z "${!name:-}" ]; then echo "::error::Missing $name; see docs/RELEASING.md"; exit 1; fi
done
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]
[[ "$APP_STORE_CONNECT_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]
[[ "$APP_STORE_CONNECT_ISSUER_ID" =~ ^[a-fA-F0-9-]{36}$ ]]
[[ "$MATCH_GIT_URL" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$ ]]
[[ "$MATCH_GIT_URL" != "https://github.com/${GITHUB_REPOSITORY}.git" ]]
repo="${MATCH_GIT_URL#https://github.com/}"; repo="${repo%.git}"
curl --fail --silent --show-error -H "Authorization: Bearer $SIGNING_GIT_TOKEN" -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$repo" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("private") is True else 1)'
key_path="$RUNNER_TEMP/toolbox-asc.p8"
printf '%s\n' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$key_path"
openssl pkey -in "$key_path" -check -noout >/dev/null 2>&1
printf 'APP_STORE_CONNECT_KEY_PATH=%s\n' "$key_path" >> "$GITHUB_ENV"
auth=$(printf 'x-access-token:%s' "$SIGNING_GIT_TOKEN" | base64 | tr -d '\n')
echo "::add-mask::$auth"
printf 'MATCH_GIT_BASIC_AUTHORIZATION=%s\n' "$auth" >> "$GITHUB_ENV"
