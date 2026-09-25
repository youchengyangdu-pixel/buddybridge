#!/usr/bin/env bash
# BuddyBridge dispatch launcher (macOS/Linux)
# 用法: launch.sh <workdir> <codebuddy args...>
# 作用：清理桌面端宿主注入的 CODEBUDDY_* 环境变量，让 CLI 以「独立终端」形态运行。
# 背景（实测 2026-09-25）：从桌面端 AI 会话内直接拉起 codebuddy 时，宿主会注入
# CODEBUDDY_CONFIG_DIR（指向宿主配置目录）与 CODEBUDDY_MCP_CONFIG（指向宿主 MCP 集群）
# 等变量，CLI 会以「宿主子进程」形态启动——连接宿主 MCP、读宿主配置，轻则行为不可控，
# 重则挂死（实测 11 分钟零产出）。
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: launch.sh <workdir> <codebuddy args...>" >&2
  exit 2
fi

WORKDIR="$1"; shift

# 只清「形态决定」变量（配置目录/宿主会话/MCP 集群/功能开关）；
# 保留 CODEBUDDY_SAFE_DELETE_BULK_GUARD（删除保护辅助路径，无害，
# 实测清掉会导致插件 marketplace 初始化失败 exit 1）
for v in CODEBUDDY_CONFIG_DIR CODEBUDDY_SESSION_ID CODEBUDDY_MCP_CONFIG \
         CODEBUDDY_CONVERSATION_MESSAGE_ID CODEBUDDY_CODE_IMAGE_COMPRESSION_MAX_DIMENSION \
         CODEBUDDY_DISABLE_SYSTEM_REMINDER_MD CODEBUDDY_DISABLE_IDE \
         CODEBUDDY_DISABLE_AUTO_MEMORY CODEBUDDY_DISABLE_FORK_SUBAGENT; do
  unset "$v" 2>/dev/null || true
done

cd "$WORKDIR"
exec codebuddy "$@"
