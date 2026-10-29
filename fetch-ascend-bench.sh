#!/usr/bin/env bash
# 一键下载并安装 Ascend Bench（用户自行执行，无需登录）。
# 下载自适应：先直连（快速超时），失败再走代理（代理地址从环境变量读，不写死）。
#   可选环境变量：
#     ASCEND_BENCH_PROXY=http://<代理IP:端口>   内网下载代理（代理一直变，改这个变量即可）
#     ASCEND_BENCH_PIP_INDEX=http://<内网pip源>/simple     pip 源（默认阿里云）
# 用法: bash fetch-ascend-bench.sh <测试容器名> <容器内持久化项目目录> [Runner端口,默认18787]
set -euo pipefail
CONTAINER="${1:?用法: bash fetch-ascend-bench.sh <测试容器名> <容器内持久化项目目录> [Runner端口,默认18787]}"
TARGET="${2:?缺少容器内持久化项目目录}"
PORT="${3:-18787}"
REPO="ZYY-ing/ascend-bench-web"
PROXY="${ASCEND_BENCH_PROXY:-}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

dl() { # $1=url $2=out $3=header $4=proxy(可空)
  local proxy="$4"
  if [ -n "$proxy" ]; then
    echo "  ↓ 下载 $1（走代理 $proxy）"
    curl -fL --connect-timeout 10 --max-time 600 --speed-time 20 --speed-limit 1024 -x "$proxy" -k ${3:+-H "$3"} "$1" -o "$2" && { echo "  ✓ 已下载 $(wc -c < "$2") 字节"; return 0; } || { echo "  ✗ 代理下载失败"; return 1; }
  else
    echo "  ↓ 下载 $1（直连）"
    curl -fL --connect-timeout 8 --max-time 120 --speed-time 10 --speed-limit 1024 --noproxy '*' ${3:+-H "$3"} "$1" -o "$2" && { echo "  ✓ 已下载 $(wc -c < "$2") 字节"; return 0; } || { echo "  ✗ 直连失败"; return 1; }
  fi
}

try_url() { # $1=url $2=out $3=header  先直连，失败再代理
  local i
  for i in 1 2; do
    if dl "$1" "$2" "$3" "" 2>/dev/null && tar tzf "$2" >/dev/null 2>&1; then return 0; fi
    rm -f "$2"
    if [ -n "$PROXY" ]; then
      if dl "$1" "$2" "$3" "$PROXY" 2>/dev/null && tar tzf "$2" >/dev/null 2>&1; then return 0; fi
      rm -f "$2"
    fi
    [ "$i" = 2 ] || { echo "  5 秒后重试"; sleep 5; }
  done
  return 1
}

OK=0
echo "== 尝试 jsdelivr CDN 下载"
try_url "https://cdn.jsdelivr.net/gh/$REPO@main/dist/ascend-bench-kit.tar.gz" "$WORK/ascend-bench-kit.tar.gz" "" && OK=1 || echo "== jsdelivr 失败"

if [ "$OK" = 0 ]; then
  echo "== 尝试 GitHub API 下载"
  # 取 release 资产 URL（同样先直连再代理）
  KURL=""
  if [ -n "$PROXY" ]; then
    KURL="$(curl -fsSL --connect-timeout 10 --max-time 40 -x "$PROXY" -k "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
      | python3 -c 'import json,sys
try:
    print([a["url"] for a in json.load(sys.stdin).get("assets",[]) if a["name"]=="ascend-bench-kit.tar.gz"][0])
except Exception:
    pass' 2>/dev/null)" || true
  else
    KURL="$(curl -fsSL --connect-timeout 10 --max-time 40 --noproxy '*' "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
      | python3 -c 'import json,sys
try:
    print([a["url"] for a in json.load(sys.stdin).get("assets",[]) if a["name"]=="ascend-bench-kit.tar.gz"][0])
except Exception:
    pass' 2>/dev/null)" || true
  fi
  if [ -n "$KURL" ]; then
    try_url "$KURL" "$WORK/ascend-bench-kit.tar.gz" "Accept: application/octet-stream" && OK=1 || echo "== GitHub API 失败"
  else
    echo "== GitHub API 不可达"
  fi
fi
[ "$OK" = 1 ] || { echo "所有下载途径均失败。内网环境请 export ASCEND_BENCH_PROXY=http://<代理IP:端口> 后重试；或手动下载压缩包后：tar xzf ascend-bench-kit.tar.gz && bash ascend-bench-kit/setup.sh $CONTAINER $TARGET"; exit 1; }

echo "== 解压并开始安装（容器 $CONTAINER → $TARGET，Runner 端口 $PORT）"
tar xzf "$WORK/ascend-bench-kit.tar.gz" -C "$WORK"
bash "$WORK/ascend-bench-kit/setup.sh" "$CONTAINER" "$TARGET" "" "$PORT"
