#!/usr/bin/env bash
# 一键下载并安装 Ascend Bench（用户自行执行，无需登录、无需特定服务器）。
# 下载顺序：jsdelivr CDN → GitHub API 资产端点 → 备用镜像，每路最多重试 2 次。
# 用法: bash fetch-ascend-bench.sh <测试容器名> <容器内持久化项目目录> [Runner端口,默认18787]
# 例:   bash fetch-ascend-bench.sh z00949185-ascend-test-minimax-m3 /home/z00949185/ascend-test
set -euo pipefail
CONTAINER="${1:?用法: bash fetch-ascend-bench.sh <测试容器名> <容器内持久化项目目录> [Runner端口,默认18787]}"
TARGET="${2:?缺少容器内持久化项目目录}"
PORT="${3:-18787}"
REPO="ZYY-ing/ascend-bench-toolkit"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

dl() { # $1=url $2=out $3=extra-header(可空)
  echo "  ↓ 下载 $1"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 20 --max-time 600 ${3:+-H "$3"} "$1" -o "$2" && { echo "  ✓ 已下载 $(wc -c < "$2") 字节"; return 0; } || { echo "  ✗ curl 失败（exit $?）"; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget --timeout=600 ${3:+--header="$3"} "$1" -O "$2" && { echo "  ✓ 已下载 $(wc -c < "$2") 字节"; return 0; } || { echo "  ✗ wget 失败"; return 1; }
  else
    echo "  本机需要 curl 或 wget"; exit 1
  fi
}

try_download() { # $1=url $2=out $3=header
  local i
  for i in 1 2; do
    echo "-- 第 $i 次尝试 --"
    if dl "$1" "$2" "$3" 2>/dev/null && tar tzf "$2" >/dev/null 2>&1; then return 0; fi
    rm -f "$2"
    [ "$i" = 2 ] || { echo "  下载或校验失败，5 秒后重试"; sleep 5; }
  done
  return 1
}

OK=0
# 1) jsdelivr CDN（国内快）
if [ "$OK" = 0 ]; then
  echo "== 尝试 jsdelivr CDN 下载"
  try_download "https://cdn.jsdelivr.net/gh/$REPO@171ba17496db/dist/ascend-bench-kit.tar.gz" "$WORK/ascend-bench-kit.tar.gz" "" && OK=1 || echo "== jsdelivr 失败"
fi
# 2) GitHub API 资产端点（绕开主站，公开仓库免 token，较慢）
if [ "$OK" = 0 ]; then
  echo "== 尝试 GitHub API 下载"
  KURL="$(curl -fsSL --connect-timeout 20 --max-time 40 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | python3 -c 'import json,sys
try:
    print([a["url"] for a in json.load(sys.stdin).get("assets",[]) if a["name"]=="ascend-bench-kit.tar.gz"][0])
except Exception:
    pass' 2>/dev/null)" || true
  if [ -n "$KURL" ]; then
    try_download "$KURL" "$WORK/ascend-bench-kit.tar.gz" "Accept: application/octet-stream" && OK=1 || echo "== GitHub API 失败"
  else
    echo "== GitHub API 不可达"
  fi
fi
# 3) 备用镜像（内网 198，可选）
if [ "$OK" = 0 ]; then
  echo "== 尝试备用镜像下载"
  try_download "http://192.168.13.198:8001/ascend-bench-kit.tar.gz" "$WORK/ascend-bench-kit.tar.gz" "" && OK=1 || echo "== 备用镜像失败"
fi
[ "$OK" = 1 ] || { echo "所有下载途径均失败。可手动下载压缩包后执行：tar xzf ascend-bench-kit.tar.gz && bash ascend-bench-kit/setup.sh $CONTAINER $TARGET"; exit 1; }

echo "== 解压并开始安装（容器 $CONTAINER → $TARGET，Runner 端口 $PORT）"
tar xzf "$WORK/ascend-bench-kit.tar.gz" -C "$WORK"
bash "$WORK/ascend-bench-kit/setup.sh" "$CONTAINER" "$TARGET" "" "$PORT"
