# cann-add-rms-norm-bias

2026 CANN 挑战赛西南赛区初赛 · AddRmsNormBias 算子

## 这是什么

昇腾 NPU（Atlas A2 / 910B）上的 Ascend C 算子开发项目，实现 `AddRmsNormBias` 融合算子（残差加法 + RMS 归一化 + 逐通道偏置），用于 CANN 算子挑战赛。

## 快速开始

**克隆仓库后必须先跑环境重建脚本**，否则缺少第三方仓库与 Python 虚拟环境：

```bash
# 1. 克隆仓库
git clone <repo-url>
cd cann-add-rms-norm-bias

# 2. 重建环境（会下载约 800MB 第三方仓库 + 建 Python 虚拟环境）
bash tools/setup_env.sh
```

`setup_env.sh` 会做四件事：

- 克隆 CANNBot skills 仓库（提供 45 个 Ascend C 开发 skill）
- 克隆三个第三方仓库（asc-devkit / cann-samples / ops-tensor）
- 重建 Python 虚拟环境（numpy + ml_dtypes，用于本地精度自验）
- 创建 `.tooling/bin/python3` 转发脚本（绕过 Windows 上 python3 指向应用商店占位程序的坑）

## 环境前提

- Windows + Git Bash（本项目在 Windows 上开发）
- Git、Python 3.10+、Node.js 18+（CANNBot 需要）
- Claude Code CLI（如果用 CANNBot 工作流）
- 需要设置环境变量 `CLAUDE_CODE_GIT_BASH_PATH`，见 `tools/setup_env.sh` 的提示

## 重要提醒：本机不能编译

> ⚠️ **本机没有 CANN Toolkit，也没有 NPU 硬件，无法编译和运行 kernel。**
> 编译和上板测性能只能通过比赛平台（CANNJudge）完成。
> CANN 仿真器（npusim）**只支持 Ascend 950 架构**，对本题的 910B 不可用。
> 因此本地只能做：算法逻辑自验（numpy）、API 查阅、代码静态检视。

## 目录结构

```
├── HANDOFF.md              # ★ 详细交接文档，先看这个
├── 1.md                    # 赛题原文
├── template/               # 官方空工程（kernel.asc 就是要填的文件）
│   ├── kernel.asc          # ★ 算子实现（目前是 TODO 空壳）
│   ├── main.asc            # 本地测试驱动
│   └── scripts/
│       ├── AddRmsNormBias.py   # numpy golden 参考实现
│       ├── gen_data.py
│       └── verify_result.py
├── src/                    # 工作副本（同 template）
├── tools/setup_env.sh      # ★ 环境重建脚本
├── .claude/                # CANNBot 的 45 个 skill + 6 个 agent
└── .cannbot/               # 工作流中间目录（第三方仓库需重建）
```

## 赛题速览

- 计算：`out = RMSNorm(x + residual, gamma) + bias`
- dtype：fp16 / bf16 / fp32
- 维度：D ∈ [64, 32768]，支持 2/3/4 维
- 精度：fp32 < 1e-4，fp16/bf16 < 1e-3
- 评分：15 个测试点全部通过才计分；**同分按提交时间排序**
- 提交限制：每天 50 次
- 详细规格见 `HANDOFF.md` 第二节

## 下一步

见 `HANDOFF.md` 第八节「下一步行动建议」。
