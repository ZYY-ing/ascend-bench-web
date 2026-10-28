#!/usr/bin/env bash
# 一键下载并安装 Ascend Bench（用户自行执行，无需登录、无需特定服务器）。
# 下载顺序：jsdelivr CDN（快，约 16 秒）→ GitHub API 资产端点 → 备用镜像 198。
# 用法: bash fetch-ascend-bench.sh <测试容器名> <容器内持久化项目目录>
# 例:   bash fetch-ascend-bench.sh z00949185-ascend-test-minimax-m3 /home/z00949185/ascend-test
set -euo pipefail
CONTAINER="${1:?用法: bash fetch-ascend-bench.sh <测试容器名> <容器内持久化项目目录> [Runner端口,默认18787]}"
TARGET="${2:?缺少容器内持久化项目目录}"
PORT="${3:-18787}"
REPO="ZYY-ing/ascend-bench-toolkit"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

dl() { # $1=url $2=out $3=extra-header(可空)
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 300 ${3:+-H "$3"} "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q ${3:+--header="$3"} "$1" -O "$2"
  else
    echo "本机需要 curl 或 wget"; exit 1
  fi
}

OK=0
# 1) jsdelivr CDN（国内最快，约 16 秒）
if [ "$OK" = 0 ]; then
  echo "== 尝试 jsdelivr CDN 下载"
  if dl "https://cdn.jsdelivr.net/gh/$REPO@171ba17496db/dist/ascend-bench-kit.tar.gz" "$WORK/ascend-bench-kit.tar.gz" "" 2>/dev/null \
     && tar tzf "$WORK/ascend-bench-kit.tar.gz" >/dev/null 2>&1; then OK=1; else rm -f "$WORK/ascend-bench-kit.tar.gz"; fi
fi
# 2) GitHub API 资产端点（绕开被墙的主站，公开仓库免 token）
if [ "$OK" = 0 ]; then
  echo "== 尝试 GitHub API 下载"
  KURL="$(curl -fsSL --max-time 30 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | python3 -c 'import json,sys
try:
    print([a["url"] for a in json.load(sys.stdin).get("assets",[]) if a["name"]=="ascend-bench-kit.tar.gz"][0])
except Exception:
    pass' 2>/dev/null)" || true
  if [ -n "$KURL" ] && dl "$KURL" "$WORK/ascend-bench-kit.tar.gz" "Accept: application/octet-stream" 2>/dev/null \
     && tar tzf "$WORK/ascend-bench-kit.tar.gz" >/dev/null 2>&1; then OK=1; else rm -f "$WORK/ascend-bench-kit.tar.gz"; fi
fi
# 3) 备用镜像（内网 198）
if [ "$OK" = 0 ]; then
  echo "== 尝试备用镜像下载"
  if dl "http://192.168.13.198:8001/ascend-bench-kit.tar.gz" "$WORK/ascend-bench-kit.tar.gz" "" 2>/dev/null \
     && tar tzf "$WORK/ascend-bench-kit.tar.gz" >/dev/null 2>&1; then OK=1; fi
fi
[ "$OK" = 1 ] || { echo "所有下载途径均失败，请检查网络（需可达 cdn.jsdelivr.net / api.github.com / 192.168.13.198）"; exit 1; }

echo "== 解压并开始安装（容器 $CONTAINER → $TARGET，Runner 端口 $PORT）"
tar xzf "$WORK/ascend-bench-kit.tar.gz" -C "$WORK"
bash "$WORK/ascend-bench-kit/setup.sh" "$CONTAINER" "$TARGET" "" "$PORT"
