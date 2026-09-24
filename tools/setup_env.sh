#!/usr/bin/env bash
# ============================================================
# CANNBot 工作区环境重建脚本（Windows / Git Bash）
#
# 用途：把 .gitignore 排除掉的第三方仓库与本地环境重新拉回来。
# 特性：幂等 —— 已存在的目录会跳过，可重复执行。
# 用法：bash tools/setup_env.sh
# ============================================================

set -euo pipefail

# ------------------------------------------------------------
# 切换到工作区根目录（脚本所在目录的父目录）
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${WORKSPACE_ROOT}"

echo "============================================================"
echo " CANNBot 工作区环境重建"
echo " 工作区根目录: ${WORKSPACE_ROOT}"
echo "============================================================"
echo

# ============================================================
# [1/6] 检查 CLAUDE_CODE_GIT_BASH_PATH 环境变量
# ============================================================
echo "[1/6] 检查 CLAUDE_CODE_GIT_BASH_PATH 环境变量 ..."
if [ -n "${CLAUDE_CODE_GIT_BASH_PATH:-}" ]; then
    echo "      已设置: ${CLAUDE_CODE_GIT_BASH_PATH}"
else
    echo "      [警告] 未设置 CLAUDE_CODE_GIT_BASH_PATH"
    echo "      CANNBot 需要该变量指向 Git Bash 可执行文件。"
    echo "      请在 PowerShell 或 CMD 中执行以下命令（本机 Git 安装在 D:\\Git）："
    echo
    echo "      reg add HKCU\\Environment /v CLAUDE_CODE_GIT_BASH_PATH /t REG_SZ /d D:\\Git\\usr\\bin\\bash.exe /f"
    echo
    echo "      执行后请重新打开终端（或重启 Claude Code）使其生效。"
fi
echo

# ============================================================
# [2/6] 克隆 CANNBot skills 仓库到 vendor/cannbot-skills
# ============================================================
echo "[2/6] 准备 vendor/cannbot-skills ..."
if [ -d "vendor/cannbot-skills" ]; then
    echo "      已存在，跳过克隆。"
else
    mkdir -p vendor
    echo "      正在克隆 cannbot-skills ..."
    echo "      [提示] 该仓库约 6275 个文件，克隆会比较慢，请耐心等待（可能数分钟）。"
    git clone --depth 1 --progress https://atomgit.com/cann/cannbot-skills.git vendor/cannbot-skills
    echo "      克隆完成。"
fi
echo "      [备注] 若上次克隆被中途打断，请手动删除 vendor/cannbot-skills 后重跑本脚本。"
echo

# ============================================================
# [3/6] 克隆三个第三方仓库到 .cannbot/
# ============================================================
echo "[3/6] 准备 .cannbot/ 下的三个第三方仓库 ..."
mkdir -p .cannbot

clone_if_missing() {
    local dir="$1"
    local url="$2"
    shift 2
    if [ -d "${dir}" ]; then
        echo "      - ${dir} 已存在，跳过。"
        return 0
    fi
    echo "      - 正在克隆 ${dir} ..."
    git clone --progress "$@" "${url}" "${dir}"
    echo "        完成: ${dir}"
}

clone_if_missing ".cannbot/asc-devkit"   "https://gitcode.com/cann/asc-devkit.git"
clone_if_missing ".cannbot/cann-samples" "https://gitcode.com/cann/cann-samples.git" --depth 1
clone_if_missing ".cannbot/ops-tensor"   "https://gitcode.com/cann/ops-tensor.git" --depth 1
echo

# ============================================================
# [4/6] 重建 Python 虚拟环境 .venv
# ============================================================
echo "[4/6] 准备 Python 虚拟环境 .venv ..."
VENV_PY=".venv/Scripts/python.exe"

if [ -x "${VENV_PY}" ]; then
    echo "      虚拟环境已存在，跳过创建。"
else
    echo "      未找到虚拟环境，正在创建 ..."
    if ! command -v python >/dev/null 2>&1; then
        echo "      [错误] 未找到 python 命令，无法创建虚拟环境。" >&2
        echo "             请先安装 Python 3.10 并确保 python 在 PATH 中。" >&2
        exit 1
    fi
    python -m venv .venv
    echo "      虚拟环境创建完成。"
fi

if [ -x "${VENV_PY}" ]; then
    if "${VENV_PY}" -c "import numpy, ml_dtypes" >/dev/null 2>&1; then
        echo "      numpy / ml_dtypes 已安装，跳过 pip 安装。"
    else
        echo "      升级 pip ..."
        "${VENV_PY}" -m pip install --upgrade pip
        echo "      安装 numpy 与 ml_dtypes ..."
        "${VENV_PY}" -m pip install numpy ml_dtypes
    fi
else
    echo "      [警告] 未找到 ${VENV_PY}，跳过依赖安装。" >&2
fi
echo

# ============================================================
# [5/6] 修复 python3 指向 Windows 应用商店占位程序的问题
#
# 本机 python3 会命中
#   C:\\Users\\Lenovo\\AppData\\Local\\Microsoft\\WindowsApps\\python3.exe
# 该占位程序被调用时静默退出，会让 CANNBot 的 init.sh 在 set -e 下中断。
# 这里用 .tooling/bin/python3 转发到真实的 Python 3.10。
# ============================================================
echo "[5/6] 创建 .tooling/bin/python3 转发脚本 ..."
mkdir -p .tooling/bin
cat > .tooling/bin/python3 <<'PYTHON3_EOF'
#!/bin/sh
exec "C:/Users/Lenovo/AppData/Local/Programs/Python/Python310/python.exe" "$@"
PYTHON3_EOF
chmod +x .tooling/bin/python3
echo "      已写入: ${WORKSPACE_ROOT}/.tooling/bin/python3"
echo
echo "      [重要] 使用时请把 .tooling/bin 加到 PATH 最前面："
printf '             export PATH="%s/.tooling/bin:$PATH"\n' "${WORKSPACE_ROOT}"
echo

# ============================================================
# [6/6] 下一步该做什么
# ============================================================
echo "[6/6] 环境重建完成。下一步："
echo
echo "  1) 确认 .tooling/bin 位于 PATH 最前面："
printf '       export PATH="%s/.tooling/bin:$PATH"\n' "${WORKSPACE_ROOT}"
echo
echo "  2) 重新运行 CANNBot 安装："
echo '       cd vendor/cannbot-skills/plugins-official/ops-direct-invoke && bash init.sh project claude "F:/2026work/hw"'
echo
echo "  [注意] 必须让 .tooling/bin 位于 PATH 最前面，"
echo "         否则 python3 会命中 Windows 应用商店占位程序并静默退出，"
echo "         导致 init.sh 在 set -e 下于第 4.5 步失败。"
echo
echo "============================================================"
echo " 全部完成。"
echo "============================================================"
