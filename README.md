# ascend-bench-toolkit

Ascend Bench 模型评测工作台部署工具包：给**已经拉起并验证过的 vLLM 服务**（Ascend 服务器）提供网页版精度 / 性能评测。浏览器操作，全程无需改代码。

---

## 前置条件（务必先满足）

### 1. vLLM 服务已拉起并通过验证

在服务器上执行以下两条命令，**均返回正常**后再继续：

```bash
curl http://<服务IP>:<端口>/health
curl http://<服务IP>:<端口>/v1/models
```

记下 `/v1/models` 返回的模型 id（served-model-name），后面网站步骤1 要用。

### 2. vLLM 服务的挂载要求

vLLM 服务所在容器需要（只读即可）：

| 挂载项 | 说明 |
|---|---|
| 模型权重目录 | 如 `/mnt/weight/home-weights/MiniMax-M3-w8a8` |
| EAGLE3 草稿权重（用了投机解码时） | 如 `/mnt/share/weight/MiniMax-M3-EAGLE3-GQA` |
| host 网络 | 服务端口直接对外 |

### 3. 测试容器的挂载要求（装本工具包的那个容器）

- **host 网络**（Runner 需能被宿主机 SSH 隧道回环访问）
- 一个**持久化 RW 挂载**的项目目录（容器内可见的 Linux 绝对路径）——安装命令里的 `<容器内持久化项目目录>` 指它，运行记录和结果都写在这里
- 容器内有 `python3`、`curl`
- 容器内能读到 **tokenizer / 权重路径**（网站步骤1 填写，用于生成测试数据和校验；只读挂载即可）

> 测试容器可以和 vLLM 服务同一个容器，也可以是独立容器，只要能访问服务 API 和 tokenizer 路径即可。

---

## 快速开始（3 步）

### 第 1 步 · 服务器宿主机（一条命令：自动下载 + 安装 + 启动）

**方式 A（推荐，一条命令）**：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-toolkit@372556a3dfa8/fetch-ascend-bench.sh -o f.sh
bash f.sh <测试容器名> <容器内持久化项目目录>
```

`f.sh`（即 `fetch-ascend-bench.sh`）会自动下载工具包压缩包、解压、安装 AISBench 环境、启动 Runner。

**方式 B（手动，拿到压缩包后）**：

```bash
curl -fL https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-toolkit@171ba17496db/dist/ascend-bench-kit.tar.gz -o ascend-bench-kit.tar.gz
tar xzf ascend-bench-kit.tar.gz
bash ascend-bench-kit/setup.sh <测试容器名> <容器内持久化项目目录>
```

两种方式二选一。安装完成后脚本会打印**隧道命令、网站地址和 token 位置**。

### 第 2 步 · 你的电脑（建立 SSH 隧道并登录）

```bash
ssh -N -o ExitOnForwardFailure=yes -L 18787:127.0.0.1:18787 <SSH用户>@<服务器IP>
```

保持隧道打开，浏览器访问 http://127.0.0.1:18787 ，粘贴 `<项目目录>/runner-token` 里的凭据登录。

### 第 3 步 · 网站内（3 个面板）

- **步骤1 · 连接推理服务**：填 服务 IP / 端口 / 模型名（`/v1/models` 返回值）/ tokenizer 路径 → 点「检查连接」——通过后自动保存到 Runner
- **步骤2 · 选择数据集**：GSM8K / AIME2026 已随包携带；GPQA 为授权数据，把 `gpqa_diamond.csv` 放入 `<项目目录>/datasets/gpqa/` 后点「重新检查」
- **步骤3 · 配置测试参数**：小批量验收建议 样本 4、并发 1、max_out_len ≥2048（思考型模型）→「开始真实测试」

切换测试目标：改步骤1 面板的服务信息 → 重新点「检查连接」，无需改服务器文件。

---

## 耗时说明

| 阶段 | 预计耗时 | 说明 |
|---|---|---|
| 下载工具包（jsdelivr CDN） | **约 16 秒** | 压缩包 5.6 MB，实测 ~340 KB/s |
| 首次安装（创建 venv + 安装 AISBench） | **约 3~5 分钟** | 需访问 pip 镜像；依赖大多已随容器存在，仅补装约 60 个包 |
| vLLM 服务本身启动 | 约 10 分钟 | 与工具包无关，是模型加载 + 图编译 |

后续再次安装（同一容器 / 已有缓存）会明显更快。

---

## Runner 端口（默认 18787，可改）

- Runner 默认监听**容器内 127.0.0.1:18787**（仅回环，只能通过 SSH 隧道访问，不对外暴露）
- **18787 不是写死的**。如果安装时检测到该端口已被占用，脚本会**明确报错退出**（绝不杀别的进程）

**换端口方法**——在安装命令最后追加一个端口号：

```bash
bash f.sh <测试容器名> <项目目录> 18788        # 方式 A
bash ascend-bench-kit/setup.sh <容器名> <项目目录> "" 18788   # 方式 B（第 3 参数 ais_bench 留空，第 4 参数是端口）
```

隧道命令同步改为：`ssh -N -L 18787:127.0.0.1:18788 <用户>@<服务器IP>`
（`-L 本地端口:远端地址:远端端口`，本地端口随便填，远端端口写你选的 18788。）

---

## 工具包下载地址（不依赖任何特定服务器）

| 通道 | 地址 |
|---|---|
| jsdelivr CDN（国内快，约 16 秒） | `https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-toolkit@171ba17496db/dist/ascend-bench-kit.tar.gz` |
| GitHub Release（固定 latest 链接） | `https://github.com/ZYY-ing/ascend-bench-toolkit/releases/latest/download/ascend-bench-kit.tar.gz` |
| 一键安装脚本 | `https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-toolkit@372556a3dfa8/fetch-ascend-bench.sh` |

`fetch-ascend-bench.sh` 的下载自动降级顺序：jsdelivr CDN → GitHub API 资产端点 → 内网镜像（`http://192.168.13.198:8001/`），全部失败才报错。

---

## 结果与文件

```
<项目目录>/results/jobs/<任务ID>/
    config.py        实际 AISBench 配置
    command.txt      实际执行命令
    execution.log    完整执行日志
    output/          原始结果 / 性能表
<项目目录>/logs/runner.log      Runner 日志
<项目目录>/runner-token         网站登录凭据
```

---

## 常见问题

- **步骤1 检查连接失败**：先做前置条件里的两条 curl；确认 IP、模型 id 是 `/v1/models` 返回值；tokenizer 路径是**服务器（测试容器内）的路径**，不是电脑路径
- **网站打不开**：检查隧道是否保持、Runner 是否在跑：`docker exec <容器> pgrep -f runner.py`，日志：`docker exec <容器> tail -20 <项目目录>/logs/runner.log`
- **端口被占用**：见「Runner 端口」一节，换端口重装
- **GPQA 未就绪**：授权数据不随包分发，自备 `gpqa_diamond.csv` 放入指定目录后重新检查

---

## 仓库内容

- `fetch-ascend-bench.sh` — 一键取包安装脚本（自动下载 + 解压 + 安装 + 启动）
- `dist/ascend-bench-kit.tar.gz` — 部署工具包（网站 + Runner + AISBench 源码 + GSM8K/AIME2026 数据集）
- GitHub Release 提供同内容的版本化资产
