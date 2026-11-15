# nonet.astlog.dev（Cloudflare）に出すための設定が、約束どおりかのテスト。
# .github/workflows/site.yml（確認と、手で出す本番）と docs/hosting.md を見る

SITE_WORKFLOW=".github/workflows/site.yml"

# deploy の job（「  deploy:」から終わりまで）
deploy_job() {
  sed -n '/^  deploy:$/,$p' "$ROOT/$SITE_WORKFLOW"
}

test_site_workflow_pins_every_action_to_a_commit() {
  local uses line pinned='uses: [a-z0-9-]+/[a-z0-9-]+@[0-9a-f]{40} # v[0-9.]+$'
  uses="$(grep -E '^[[:space:]]*-?[[:space:]]*uses:' "$ROOT/$SITE_WORKFLOW" || true)"
  [[ -n "$uses" ]] || fail "$SITE_WORKFLOW に uses: がありません"
  while IFS= read -r line; do
    [[ "$line" =~ $pinned ]] ||
      fail "action を commit の SHA（とタグ名のコメント）で固定していません: $line"
  done <<<"$uses"
  grep -qx 'permissions:' "$ROOT/$SITE_WORKFLOW" || fail "permissions: がありません"
  grep -qx '  contents: read' "$ROOT/$SITE_WORKFLOW" || fail "permissions が contents: read だけになっていません"
}

test_site_workflow_checks_when_the_site_or_worker_changes() {
  local path
  for path in '"site/**"' '"cloudflare/**"' '"scripts/check-site.sh"' '"scripts/publish.sh"'; do
    assert_eq 2 "$(grep -cF -- "- $path" "$ROOT/$SITE_WORKFLOW")" "push と pull_request の両方の paths に $path"
  done
  grep -qx '  workflow_dispatch:' "$ROOT/$SITE_WORKFLOW" || fail "手で実行できません（workflow_dispatch）"
  assert_contains "$(cat "$ROOT/$SITE_WORKFLOW")" "run: scripts/check-site.sh"
  assert_contains "$(cat "$ROOT/$SITE_WORKFLOW")" "run: node --test test/*.test.js"
  assert_contains "$(cat "$ROOT/$SITE_WORKFLOW")" "run: npx wrangler deploy --dry-run"
}

# 本番へ出すのは、手で実行したときだけ・main から・承認のあと・仮の値が無いときだけ
test_site_workflow_deploys_only_by_hand_after_the_strict_check() {
  local job
  job="$(deploy_job)"
  [[ -n "$job" ]] || fail "$SITE_WORKFLOW に deploy の job がありません"
  assert_contains "$job" "if: github.event_name == 'workflow_dispatch'"
  assert_contains "$job" "needs: [guard, check]"
  assert_contains "$job" "environment: production"
  assert_contains "$job" "cancel-in-progress: false"
  assert_contains "$job" "run: npm ci --ignore-scripts"
  assert_contains "$(sed -n '/^  guard:$/,/^  deploy:$/p' "$ROOT/$SITE_WORKFLOW")" "if: github.ref != 'refs/heads/main'"
  local strict deploy
  strict="$(grep -n 'scripts/check-site.sh --strict' <<<"$job" | head -n 1 | cut -d: -f1)"
  deploy="$(grep -nx '          npx wrangler deploy' <<<"$job" | head -n 1 | cut -d: -f1)"
  [[ -n "$strict" && -n "$deploy" && "$strict" -lt "$deploy" ]] ||
    fail "deploy の job で、scripts/check-site.sh --strict が wrangler deploy より前にありません"
}

# トークンは production の environment の secret から、wrangler を呼ぶ step の env にだけ渡す
test_site_workflow_keeps_the_token_in_the_wrangler_step() {
  assert_eq 1 "$(grep -c 'secrets\.CLOUDFLARE_API_TOKEN' "$ROOT/$SITE_WORKFLOW")" "トークンを読むところの数"
  assert_eq 1 "$(deploy_job | grep -c 'CLOUDFLARE_API_TOKEN: \${{ secrets.CLOUDFLARE_API_TOKEN }}')" "deploy の job の中で読む"
  ! grep -qE '^(  |    )?env:' "$ROOT/$SITE_WORKFLOW" || fail "workflow や job の env: にトークンを置かない（step の env にだけ）"
  # トークンを読む step（env: の次の行から run: の終わりまで）で wrangler deploy を呼ぶ
  assert_contains "$(deploy_job | sed -n '/CLOUDFLARE_API_TOKEN: \${{/,$p')" "npx wrangler deploy"
}

test_hosting_doc_covers_publish_and_setup() {
  local doc="$ROOT/docs/hosting.md" text name
  assert_file "$doc"
  text="$(cat "$doc")"
  for name in $(sed -n '/^usage()/,/^}/p' "$ROOT/scripts/publish.sh" | grep -oE 'NONET_[A-Z_]+|CLOUDFLARE_[A-Z_]+|--[a-z-]+' | sort -u); do
    assert_contains "$text" "$name" "docs/hosting.md に publish.sh の $name の説明がありません"
  done
  for name in "scripts/publish.sh" "wrangler r2 bucket create nonet-updates" "Workers Routes" "Workers R2 Storage" \
    "appcast-history" "wrangler rollback" "single-page-application" "r2.dev" "Required reviewers"; do
    assert_contains "$text" "$name" "docs/hosting.md"
  done
}
