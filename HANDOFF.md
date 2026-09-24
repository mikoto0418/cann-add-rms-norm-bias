# AddRmsNormBias 项目交接文档（HANDOFF）

> 本文档面向 AI 助手，用于快速接手本项目。人类读者同样适用。

**文档定位**：让接手方（AI 会话或人 + AI）在 10 分钟内完全理解项目现状、环境约束、已有情报与下一步行动。信息密度优先，结论均标注依据来源。

---

## 一、项目速览

| 项 | 内容 |
|---|---|
| 项目 | 2026 年 CANN 挑战赛（昇腾 AI 算子挑战赛）西南赛区初赛 |
| 赛题 | AddRmsNormBias 融合算子 |
| 目标芯片 | Atlas A2（910B，npu-arch `dav-2201`） |
| CANN 版本 | 9.0.0 |
| 赛程 | 2026/09/05 - 2026/10/17 |
| 提交限制 | 每天最多 50 次；取比赛期间**最后一次**提交的成绩 |

**评分规则**

- 15 个测试点**全部精度通过**才计分（任一点不过 = 0 分）。
- 单点得分：

  ```
  score = 100 / (1 + log1.5(t / T))
  ```

  其中 `t` 为本次提交该点的耗时，`T` 为最优耗时。
- 最终分为所有 case 的均分。
- **同分按提交时间排序，越早越靠前。**

**关键约束（赛事原文）**

> 本次赛要求核心计算在昇腾 NPU 上通过 AscendC 算子实现完成，任何将计算转移至 Host CPU、通过空 kernel 占位绕过 NPU 计算要求的行为，均构成违规，将取消当前提交成绩。

---

## 二、算子规格

### 2.1 计算定义（三步融合）

```
Step 1: y = x + residual
Step 2: rms = sqrt(mean(y^2, dim=-1) + eps); z = y / rms * gamma
Step 3: out = z + bias
```

等价 PyTorch 写法：

```python
torch.nn.functional.rms_norm(x + residual, normalized_shape, weight=gamma, eps=epsilon) + bias
```

### 2.2 输入输出

| 类型 | 参数名 | 形状 | dtype | 说明 |
|---|---|---|---|---|
| INPUT | x | (..., D) | fp16/bf16/fp32 | 主输入 |
| INPUT | residual | (..., D) | 同 x | 残差，shape 与 x 完全一致 |
| INPUT | gamma | (D,) | 同 x | RMS 缩放系数 |
| INPUT | bias | (D,) | 同 x | 逐通道偏置，加在归一化之后 |
| ATTR | epsilon | float | - | 默认 1e-5 |
| OUTPUT | output | (..., D) | 同 x | 结果 |

### 2.3 维度约束

- 支持 2 维 `(batch, D)`、3 维 `(batch, seq, D)`、4 维 `(batch, seq, heads, D)`。
- `batch ∈ [1, 8192]`，`seq_len ∈ [1, 32768]`，`D ∈ [64, 32768]`。
- **D 可能是非 32 整倍数**（如 192、576），必须处理非对齐。
- `residual` 与 `x` 的 shape 必须完全一致。

### 2.4 精度要求

| dtype | 相对误差 | 绝对误差 |
|---|---|---|
| fp32 | < 1e-4 | < 1e-4 |
| fp16 / bf16 | < 1e-3 | < 1e-3 |

### 2.5 特殊值

NaN / Inf 输入不能崩溃，按数学公式传播。

---

## 三、本机环境现状（关键）

本章决定"哪些事能本地做、哪些必须上平台"，是排期与提交策略的根本依据。

### 3.1 不能做的

| 能力 | 状态 | 依据 |
|---|---|---|
| **编译** | ❌ 不可用 | 本机没有 CANN Toolkit，`/usr/local/Ascend` 不存在，`find_package(ASC)` 找不到。只有比赛平台的评测机能编译 |
| **上板运行 / 精度实测** | ❌ 不可用 | 没有 NPU 硬件，`npu-smi` 命令不存在 |
| **性能采集（msprof）** | ❌ 不可用 | 必须上板 |
| **CANN 仿真器（npusim）** | ❌ 对本题不可用 | **该仿真器只支持 Ascend 950 架构**（skill 文档原文："芯片限制：仅支持 Ascend 950 芯片架构"），而本赛题是 910B（dav-2201）。仿真这条路对本题**完全不可用** |
| **WSL** | ❌ 不可用 | `Ubuntu` 发行版已损坏（`ext4.vhdx` 缺失，启动报 `Wsl/Service/CreateInstance/MountDisk/HCS/ERROR_FILE_NOT_FOUND`） |

### 3.2 能做的

- ✅ 读题、方案设计、写 kernel 代码（纯文本工作）。
- ✅ **精度逻辑本地自验**：赛题模板的 golden 是纯 numpy 实现（`template/scripts/AddRmsNormBias.py`），不依赖 NPU。工作区已建好 `.venv`（numpy 2.2.6 + ml_dtypes 0.6.0），可以先用 numpy 把算法逻辑验干净。
- ✅ API 文档查阅：`.cannbot/asc-devkit`（567MB）含完整头文件和文档。
- ✅ 代码静态检视：`ascendc-code-review`、`repo-coding-rules` 等 skill。

### 3.3 由此得出的策略

本地把能验的都验干净（算法逻辑、精度预期、代码红线），把宝贵的每日 50 次提交额度留给真正需要平台反馈的编译错误和性能数据。

### 3.4 已知的 Windows 坑（必读）

1. `python3` 指向 Windows 应用商店占位程序，调用即静默退出，会让 CANNBot 的 `init.sh` 在 `set -e` 下中断。解决办法见 `tools/setup_env.sh`。
2. `setx` 写环境变量会把引号一起写进去，导致 Claude CLI 找不到 git-bash。正确写法用 `reg add`。
3. Claude Code 需要 `CLAUDE_CODE_GIT_BASH_PATH` 指向 `D:\Git\usr\bin\bash.exe`（注意：必须反斜杠，正斜杠会被判为无效路径）。
4. Windows 下 `ln -sfn` 会退化成复制而非符号链接。CANNBot 装的 skills 因此是实体目录（好处：可移植，不依赖链接）。

---

## 四、工具链现状

工作区已安装 CANNBot 的 `ops-direct-invoke` 插件（project 级、claude 工具）。

### 4.1 Skills（45 个，位于 `.claude/skills/`）

与本题最相关的：

| Skill | 用途 |
|---|---|
| `ascendc-tiling-design` | Tiling 设计方法论（多核切分 / UB 切分 / Buffer 规划） |
| `ascendc-api-best-practices` | API 正确用法与限制 |
| `ascendc-direct-invoke-template` | Kernel 直调工程模板（含 add_custom 样例） |
| `ascendc-perf-optimize` / `ascendc-performance-best-practices` | 性能优化 |
| `ascendc-precision-debug` | 精度问题诊断 |
| `npu-arch` | 芯片架构知识 |
| `ops-profiling` | 性能采集（需上板） |
| `ops-precision-standard` | 精度标准 |
| `ops-simulator` | 仿真器（**对本题不可用，仅支持 950**） |

### 4.2 Agents（6 个，位于 `.claude/agents/`）

| Agent | 职责 |
|---|---|
| `architect` | 方案设计 |
| `developer-code` | 代码 |
| `developer-test` | 测试 / golden |
| `developer-doc` | 文档 |
| `developer` | 综合 |
| `qa` | 验收 |

### 4.3 权限 hook

`.claude/hooks/permission-guard.js` 会按角色拦截写操作。**PM（主线程）只能写 `.cannbot/` 目录，代码必须派给 `developer-code`。** 这是 CANNBot 的刻意设计。

### 4.4 三个第三方仓库（用 `tools/setup_env.sh` 重建）

| 仓库 | 体积 | 内容 |
|---|---|---|
| `.cannbot/asc-devkit` | 567MB | Ascend C 开发套件，含 `include/`、`docs/`、`examples/` |
| `.cannbot/cann-samples` | 227MB | 官方样例 |
| `.cannbot/ops-tensor` | 7.3MB | — |

---

## 五、调研情报（可直接指导实现）

### 5.1 官方已有同名算子实现，不要从零发明

CANN 官方仓库 `ops-nn` 里有 `norm/add_rms_norm/`，MindSpeed-Ops 里有 `add_rms_norm_bias/`，vllm-ascend 里也有。**比赛的 baseline / T_HW 大概率就是这套实现标定的。**

关键源码路径（可用 `curl` 抓 `raw.gitcode.com`；注意 **WebFetch 对 gitcode.com 会被安全策略拦截**）：

```
raw.gitcode.com/cann/ops-nn/raw/master/norm/add_rms_norm/op_host/add_rms_norm_tiling.cpp
raw.gitcode.com/cann/ops-nn/raw/master/norm/add_rms_norm/op_kernel/add_rms_norm_split_d.h
raw.gitcode.com/cann/ops-nn/raw/master/norm/rms_norm/op_kernel/rms_norm_base.h
raw.gitcode.com/cann/ops-nn/raw/master/norm/rms_norm/op_kernel/reduce_common.h
raw.gitcode.com/Ascend/MindSpeed-Ops/raw/master/mindspeed_ops/csrc/add_rms_norm_bias/op_host/add_rms_norm_bias_tiling.cpp
```

### 5.2 官方 tiling 的关键常量（原文提取）

```cpp
constexpr uint32_t UB_USED = 1024;
constexpr uint32_t UB_FACTOR_B16 = 12288,  UB_FACTOR_B32 = 10240;
constexpr uint32_t UB_FACTOR_B16_CUTD = 12096, UB_FACTOR_B32_CUTD = 9696;
constexpr uint32_t SMALL_REDUCE_NUM = 2000;
constexpr uint32_t BLOCK_ALIGN_NUM = 16, FLOAT_BLOCK_ALIGN_NUM = 8;
constexpr uint32_t FLOAT_PER_REPEAT = 64, USE_SIZE = 256;
// 模式：NORMAL=0, SPLIT_D=1, MERGE_N=2, SINGLE_N=3, MULTI_N=4
// tilingKey = dtypeKey * 10 + modeKey（fp16=1, fp32=2, bf16=3）
```

**模式判定顺序**：

1. D 超过 `ubFactor` → `SPLIT_D`（沿 D 切）
2. `blockFactor == 1` → `SINGLE_N`
3. `numColAlign ≤ 2000` → `MERGE_N`
4. fp16 且对齐 → `MULTI_N`
5. 否则 `NORMAL`

**切核方式**：纯按行切分，`blockFactor = CeilDiv(numRow, numCore)`，尾核单独处理。

### 5.3 官方归约算法（性能关键）

官方不用单条 `WholeReduceSum`，而是"先用 `Add` 把 `repeatTimes` 个 repeat 折进同一个 64 元素窗口，最后只发一条 `WholeReduceSum`"：

```cpp
uint64_t mask = 64;                       // NUM_PER_REP_FP32
int32_t repeatTimes = count / 64, tailCount = count % 64;
BinaryRepeatParams repeatParams;
repeatParams.src0RepStride = 8;           // 256B/32B
repeatParams.src0BlkStride = 1;
repeatParams.src1RepStride = 0;           // 第二个操作数重复读同一窗口
repeatParams.dstRepStride  = 0;           // 累加到同一窗口
Duplicate(work_local, ZERO, 64);
Add(work_local, src_local, work_local, mask, repeatTimes, repeatParams);
Add(work_local, src_local[bodyCount], work_local, tailCount, 1, repeatParams);
AscendCUtils::SetMask(64);
WholeReduceSum(dst_local, work_local, MASK_PLACEHOLDER, 1, 0, 1, 0);
```

**官方实测数据**（昇腾文档）：shape=30000 float 场景下，二分累加 172 cycle，而单条 `WholeReduceSum` 要 242 cycle（慢 29%）。

**选型建议**：

| 数据规模 | 建议方案 |
|---|---|
| ≤ 256B | 单指令 |
| 256B ~ 2KB | Block + Whole 组合 |
| 2KB ~ 16KB | 2 × `WholeReduceSum` |
| > 16KB | 二分累加 |

**`ReduceSum` API 内含 Scalar 同步会阻塞 Vector 流水，性能敏感场景禁用。**

### 5.4 官方实现的三个可打败点

| # | 问题 | 机会 |
|---|---|---|
| 1 | **910B 路径默认单缓冲**：`rms_norm_base.h` 里 `constexpr int32_t BUFFER_NUM = 1;`，只有 multi_n 模式用了双缓冲 | 开双缓冲是明确的收益点 |
| 2 | **split_d 为三输出设计**：官方 AddRmsNorm 要输出 y / rstd / x_out 三个张量，D 大时会写 `xGm` 中间结果再读回来，HBM 往返约 5 趟 | **本赛题只有一个 output**，可以砍掉中间写回，改成"不落中间结果的两遍纯读" |
| 3 | **rstd 计算用了三步**：官方是 `Adds(eps)` → `Sqrt` → `Duplicate(ONE)` → `Div`，共 3 条指令 + 3 个 PipeBarrier | 换成一条 `Rsqrt` 可省 2 条指令和 2 个 barrier（需实测精度，1e-3 阈值下大概率够） |

### 5.5 硬件规格（Atlas A2 910B）

| 项 | 值 |
|---|---|
| Vector Core | 48（910B2）/ 40（B3、B4） |
| UB | 192 KB / AIV |
| L1 | 512 KB |
| L2 | 192 MB |
| 一 repeat | 256 字节（fp32 = 64 个，fp16 = 128 个） |
| repeatTimes 上限 | 255 |
| AIC : AIV | 1 : 2 |

**必须用 `GetCoreNumAiv()` / `GetCoreMemSize(CoreMemType::UB)` 取实际值，不要硬编码。**

### 5.6 搬运 API 的关键事实

- 910B 上官方一律用 `DataCopyPad` 处理非对齐。
- `DataCopyExtParams` 的 `blockLen` 单位是**字节**，不是元素。
- `srcStride` / `dstStride` 单位：GM 侧是字节，VECIN/VECOUT 侧是 dataBlock（32 字节）。
- pad 区域填 0，不影响归约；但 `avgFactor` 必须用**真实 numCol**，不能用对齐后的值。
- **陷阱**：`GatherMask` 会隐式修改全局掩码，必须用局部掩码或及时恢复。

### 5.7 评分与策略

- 15 个测试点全部精度通过才计分（任何一点不过 = 0 分）。
- 单点：`100 / (1 + log1.5(t/T))`，`t` 是本次耗时、`T` 是最优耗时。
- **同分按提交时间排序** → 策略上应该**先提交一个能过精度的保守版本占位，再迭代性能**。

---

## 六、目录结构说明

```
F:\2026work\hw\
├── 1.md                          # 赛题原文
├── HANDOFF.md                    # 本文档
├── AGENTS.md / CLAUDE.md         # CANNBot 的 PM 入口（init.sh 生成）
├── addrmsnormbias_problem_1742_template.zip   # 官方空工程
├── template/                     # 解压后的空工程
│   ├── CMakeLists.txt            # ASC 语言，--npu-arch=dav-2201
│   ├── kernel.asc                # ★ 要填的就是这个文件（目前是 TODO 空壳）
│   ├── main.asc                  # 本地测试驱动
│   ├── data_utils.h
│   ├── run.sh
│   └── scripts/
│       ├── AddRmsNormBias.py     # ★ numpy golden 参考实现
│       ├── gen_data.py           # 测试数据生成
│       └── verify_result.py      # 结果校验
├── src/                          # 工作副本（同 template）
├── .claude/                      # CANNBot skills + agents + hooks
├── .cannbot/                     # 工作流中间目录 + 三个第三方仓库（需重建）
├── .venv/                        # Python 虚拟环境（需重建）
├── .tooling/bin/python3          # python3 转发脚本（需重建）
├── tools/setup_env.sh            # ★ 环境重建脚本
└── vendor/cannbot-skills/        # CANNBot 源仓库（需重建）
```

**注意**：`template/` 和 `src/` 内容相同，是同一份工程的两个副本。

---

## 七、kernel.asc 的入口契约

这是本题最特殊的架构点。

```cpp
extern "C" void run_kernel(
    GM_ADDR x, const TensorGroupInfo& info_x,
    GM_ADDR residual, const TensorGroupInfo& info_residual,
    GM_ADDR gamma, const TensorGroupInfo& info_gamma,
    GM_ADDR bias, const TensorGroupInfo& info_bias,
    GM_ADDR output, const TensorGroupInfo& info_output,
    int64_t availableCoreNum, aclrtStream stream, float epsilon)
{
    // 在这里手算 tiling，然后启动 kernel
    // add_rms_norm_bias_custom<<<blockNum, nullptr, stream>>>(...);
}
```

**关键差异**：这里**没有** `gert::TilingContext`——不像标准算子工程那样由框架算 tiling。必须在 `run_kernel` 里**手工计算 tiling**（用 `info_x.tensors[0].shape` / `numDims` / `dtype` + `availableCoreNum`），再传给 kernel。

**预定义结构体**：

```cpp
struct TensorInfo { const int64_t* shape; int64_t numDims; int32_t dtype; };
struct TensorGroupInfo { const TensorInfo* tensors; int64_t numTensors; };
// dtype: 0=fp32 1=fp16 2=bf16 3=int8 4=int16 5=int32 6=int64 ...
// 用法: info_x.tensors[0].shape[0]
```

**`kernel.asc` 是被 `#include` 的，不要加 `main()`、`#pragma once` 或 include guard。**

---

## 八、下一步行动建议

按优先级排序：

1. **先出一版能过的保守实现**，尽快提交占位（利用"同分按时间排序"规则）。
2. 本地用 numpy 验证算法逻辑（`.venv` 已就绪）。
3. 针对官方三个可打败点做优化：**双缓冲**、**去掉中间写回**、**Rsqrt**。
4. 每次提交前用 `ascendc-code-review` skill 自查。
5. 记录每次提交的得分与耗时，反推 `T`（最优耗时）的量级。

---

## 九、参考链接

| 用途 | 链接 |
|---|---|
| 赛事主页 | https://competition.gitcode.com/competition/2094722165106008066/publish |
| 答题入口 | https://cannjudge.cn/public/op_challenge_xinan_prelim/addrmsnormbias |
| CANNBot skills 仓库 | https://atomgit.com/cann/cannbot-skills |
| CANN ops-nn | https://gitcode.com/cann/ops-nn |
| 历届提交存档 | https://gitcode.com/cann/cann-ops-competitions |
| cann-bench（含 t_hw 与 golden） | https://gitcode.com/cann/cann-bench |
