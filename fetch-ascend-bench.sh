#!/usr/bin/env bash
# 下载 main 的提交快照并校验安装包；不接受 CDN @main 的旧包。
# 用法: bash fetch-ascend-bench.sh <测试容器名> <容器内持久化项目目录> [Runner端口,默认18787]
# 只下载不安装: bash fetch-ascend-bench.sh --download-only [保存目录]
# ASCEND_BENCH_PROXY / ASCEND_BENCH_PIP_INDEX / ASCEND_BENCH_EXTRA_HOSTS 沿用原安装方式。
# ASCEND_BENCH_REF 可指定已确认的完整 40 位提交 SHA；未指定时查询 main。
set -euo pipefail
MODE=install
if [ "${1:-}" = '--download-only' ]; then
  MODE=download
  OUTPUT="${2:-./ascend-bench-download}"
else
  CONTAINER="${1:?用法: bash fetch-ascend-bench.sh <测试容器名> <容器内持久化项目目录> [Runner端口,默认18787]}"
  TARGET="${2:?缺少容器内持久化项目目录}"
  PORT="${3:-18787}"
fi
REPO="ZYY-ing/ascend-bench-web"
PROXY="${ASCEND_BENCH_PROXY:-}"
REF="${ASCEND_BENCH_REF:-}"
KIT="ascend-bench-kit.tar.gz"
for tool in curl python3 tar sha256sum; do
  command -v "$tool" >/dev/null || { echo "缺少宿主机工具：$tool" >&2; exit 1; }
done
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

dl() { # url, output, optional header, optional proxy
  local proxy="$4"
  local args=(-fL --connect-timeout 10 --max-time 180 --speed-time 20 --speed-limit 1024 -H 'Cache-Control: no-cache')
  [ -z "$3" ] || args+=(-H "$3")
  if [ -n "$proxy" ]; then
    echo "  ↓ 下载 $1（使用配置的代理）"
    # 保留既有代理下载兼容方式；与之前一样，代理分支使用 -k。
    args+=(-x "$proxy" -k)
  else
    echo "  ↓ 下载 $1（直连）"
    args+=(--noproxy '*')
  fi
  curl "${args[@]}" "$1" -o "$2"
}

try_url() { # url, output, optional header, validation function
  local i
  for i in 1 2; do
    if dl "$1" "$2" "$3" "" 2>/dev/null && "$4" "$2"; then return 0; fi
    rm -f "$2"
    if [ -n "$PROXY" ]; then
      if dl "$1" "$2" "$3" "$PROXY" 2>/dev/null && "$4" "$2"; then return 0; fi
      rm -f "$2"
    fi
    [ "$i" = 2 ] || sleep 3
  done
  return 1
}

verify_ref() {
  python3 - "$1" "$WORK/ref" <<'PY'
import json,re,sys
from pathlib import Path
try:
    value=json.loads(Path(sys.argv[1]).read_text())['sha']
    if not isinstance(value,str) or not re.fullmatch('[0-9a-f]{40}',value):raise ValueError()
    Path(sys.argv[2]).write_text(value)
except (OSError,ValueError,KeyError,TypeError):
    raise SystemExit('无法从 GitHub 响应确认 main 提交，未开始安装')
PY
}

verify_checksum() {
  python3 - "$1" "$KIT" <<'PY'
import re,sys
from pathlib import Path
try:
    fields=Path(sys.argv[1]).read_text(encoding='ascii').split()
    if len(fields)!=2 or not re.fullmatch('[0-9a-fA-F]{64}',fields[0]) or fields[1]!=sys.argv[2]:raise ValueError()
    Path(sys.argv[1]).write_bytes((fields[0].lower()+'  '+sys.argv[2]+'\n').encode('ascii'))
except (OSError,ValueError,UnicodeError):
    raise SystemExit('安装包 SHA256 文件格式无效，拒绝此下载源')
PY
}

git_ref() {
  command -v git >/dev/null || return 1
  GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c core.askPass= -c "http.proxy=$PROXY" \
    ls-remote --exit-code "https://github.com/$REPO.git" refs/heads/main > "$WORK/git-ref" 2>/dev/null || return 1
  python3 - "$WORK/git-ref" "$WORK/ref" <<'PY'
import re,sys
from pathlib import Path
fields=Path(sys.argv[1]).read_text().split()
if len(fields)!=2 or fields[1]!='refs/heads/main' or not re.fullmatch('[0-9a-f]{40}',fields[0]):
    raise SystemExit('无法通过 Git 确认 main 版本')
Path(sys.argv[2]).write_text(fields[0])
PY
}

verify_kit() {
  if ! (cd "$WORK" && sha256sum -c "$KIT.sha256"); then
    echo '安装包 SHA256 不匹配，拒绝此下载源；不会执行 setup.sh' >&2
    return 1
  fi
  tar tzf "$1" >/dev/null 2>&1
}

if [ -z "$REF" ]; then
  echo '== 查询 main 当前提交（先确认版本，再下载）'
  try_url "https://api.github.com/repos/$REPO/commits/main?fresh=$(date +%s)" "$WORK/main.json" 'Accept: application/vnd.github+json' verify_ref || git_ref || {
    echo '当前网络无法确认 GitHub main 最新版本，已停止；请检查网络/代理或稍后重试，不会改装旧包。' >&2
    exit 1
  }
  REF="$(cat "$WORK/ref")"
fi
[[ "$REF" =~ ^[0-9a-f]{40}$ ]] || { echo 'ASCEND_BENCH_REF 必须是完整40位小写提交SHA，不能填写 main 或短SHA' >&2; exit 1; }
echo "== 已自动确认 GitHub 版本：${REF:0:12}（无需手动填写）"
RAW="https://raw.githubusercontent.com/$REPO/$REF/dist/$KIT"
API="https://api.github.com/repos/$REPO/contents/dist/$KIT"
CDN="https://cdn.jsdelivr.net/gh/$REPO@$REF/dist/$KIT"

try_url "$RAW.sha256" "$WORK/$KIT.sha256" '' verify_checksum ||
try_url "$API.sha256?ref=$REF" "$WORK/$KIT.sha256" 'Accept: application/vnd.github.raw+json' verify_checksum ||
try_url "$CDN.sha256" "$WORK/$KIT.sha256" '' verify_checksum || {
  echo '无法获取该提交的有效 SHA256 文件，未开始安装' >&2; exit 1;
}

try_url "$RAW" "$WORK/$KIT" '' verify_kit ||
try_url "$API?ref=$REF" "$WORK/$KIT" 'Accept: application/vnd.github.raw+json' verify_kit ||
try_url "$CDN" "$WORK/$KIT" '' verify_kit || {
  echo '该提交的安装包下载或校验失败，未开始安装；不会退回 CDN @main 或旧 Release。' >&2; exit 1;
}

if [ "$MODE" = download ]; then
  mkdir -p -- "$OUTPUT"
  cp -- "$WORK/$KIT" "$OUTPUT/$KIT"
  cp -- "$WORK/$KIT.sha256" "$OUTPUT/$KIT.sha256"
  printf '%s\n' "$REF" > "$OUTPUT/source-commit.txt"
  echo "== 已下载并校验到 $OUTPUT；未执行安装、未操作容器或 Runner"
  exit 0
fi
echo "== 校验通过，开始安装（容器 $CONTAINER → $TARGET，Runner 端口 $PORT）"
tar xzf "$WORK/$KIT" -C "$WORK"
bash "$WORK/ascend-bench-kit/setup.sh" "$CONTAINER" "$TARGET" "" "$PORT"
