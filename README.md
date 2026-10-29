# Ascend Bench Web

给**已经拉起并验证过的 vLLM 服务**（Ascend 服务器）提供的网页版模型评测工作台。浏览器操作，精度 / 性能测试全程无需改代码。

---

## 前提

1. vLLM 服务已成功拉起，且服务器上以下两条命令**均返回正常**：

   ```bash
   curl http://<服务IP>:<端口>/health
   curl http://<服务IP>:<端口>/v1/models
   ```

   记下 `/v1/models` 返回的模型 id（served-model-name），网站步骤1 要用。

2. 有一台能运行 `docker` 的宿主机，以及一个 **host 网络**的测试容器。

---

## 挂载要求（只读/已有即可，通常无需额外配置）

**测试容器**（装本工具包的那个容器）需要：

- **host 网络**：Runner 只监听容器内 127.0.0.1，靠宿主机 SSH 隧道回环访问
- 一个**持久化 RW 目录**：安装命令里的 `<容器内持久化项目目录>`，宿主机和容器都要能看到它（bind-mount 或 `-v` 挂载），记录和结果都写在这里
- 容器内有 `python3`、`curl`
- 容器内能读到 **tokenizer / 权重路径**（网站步骤1 填写，用于生成测试数据，只读挂载即可）
---

## 快速开始（3 步）

### 第 1 步 · 服务器宿主机（下载 + 安装）

**情况一 · 外网直连（无需代理，零配置）**：

下载fetch-ascend-bench.sh：脚本内自行下载工具包并解压执行

```bash
curl -fL https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-web@main/fetch-ascend-bench.sh -o f.sh
bash f.sh <测试容器名> <容器内持久化项目目录>
```
或者直接下载压缩包--解压--执行setup

```bash
curl -fL https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-web@main/dist/ascend-bench-kit.tar.gz -o ascend-bench-kit.tar.gz
tar xzf ascend-bench-kit.tar.gz
bash ascend-bench-kit/setup.sh <测试容器名> <容器内持久化项目目录>
```

**情况二 · 内网代理（完整脚本，3 个变量 + 2 条命令）**：


##### 1) 环境变量（代理、内网 pip 源、可选的内网域名解析）
```bash
export ASCEND_BENCH_PROXY=http://<代理IP:端口>          # 例 111.1.111.180:3128，curl 下载和 pip 安装共用
# 如果内网有更快的 pip 镜像（直连可达）;不设 `ASCEND_BENCH_PIP_INDEX` 时 pip 用默认的阿里云源（配合上面的代理走）。
export ASCEND_BENCH_PIP_INDEX=http://<内网pip源>/simple  # 例 http://mirrors.tools.huawei.com/pypi/simple，pip
export ASCEND_BENCH_EXTRA_HOSTS="<内网源IP> <内网源域名>" # 可选，容器解析不了内网域名时
```
##### 2) 下载脚本并安装  
步骤跟 **情况一** 基本一样
```bash
curl -fL -x "$ASCEND_BENCH_PROXY" -k \
  https://github.com/ZYY-ing/ascend-bench-web/releases/latest/download/fetch-ascend-bench.sh -o f.sh
bash f.sh <测试容器名> <容器内持久化项目目录>
```
或者
```bash
curl -fL -x "$ASCEND_BENCH_PROXY" -k https://github.com/ZYY-ing/ascend-bench-web/releases/latest/download/ascend-bench-kit.tar.gz -o ascend-bench-kit.tar.gz
tar xzf ascend-bench-kit.tar.gz
bash ascend-bench-kit/setup.sh <测试容器名> <容器内持久化项目目录>
```

>`ASCEND_BENCH_PROXY` 设了之后：

>- **下载（curl）**：`fetch-ascend-bench.sh` 会先直连快速试一次，失败自动走 `-x $ASCEND_BENCH_PROXY -k`（`-k` 跳过代理中间人证书，netentsec 类会拦 SSL）
>- **安装（pip）**：setup.sh 会把 `proxy = $ASCEND_BENCH_PROXY` 写进 pip 配置，pip 下载依赖也走这套代理

> 代理地址经常变？改 `ASCEND_BENCH_PROXY` 这一个变量即可，脚本一个字节都不用动。排查口诀：下载卡 → `env | grep -i proxy` 看有没有打架的旧代理变量（脚本里已用 `--noproxy '*'` 绕开）；pip 慢 → 设 `ASCEND_BENCH_PIP_INDEX` 走内网源。

### 第 2 步 · 你的电脑（建隧道 + 登录）
Runner 端口（默认 18787 监听容器内 `127.0.0.1:18787`）

在本机powershell内执行：
```bash
ssh -N -o ExitOnForwardFailure=yes -L <本地端口>:127.0.0.1:18787 <SSH用户>@<服务器IP>
```
浏览器打开 http://127.0.0.1:18787  ，粘贴服务器 `<项目目录>/runner-token` 里的凭据登录。

#### 若多台机器同时用

每台机器映射**一个不同的本地端口**建隧道，浏览器各开一个标签页，登录态互不干扰（cookie 按本地端口隔离）：
```bash
ssh -N -L 18787:127.0.0.1:18787 <用户>@<机器1>   # 标签页1: http://127.0.0.1:18787
ssh -N -L 18788:127.0.0.1:18787 <用户>@<机器2>   # 标签页2: http://127.0.0.1:18788
ssh -N -L 18789:127.0.0.1:18787 <用户>@<机器3>   # 标签页3: http://127.0.0.1:18789
```
> 本地端口随便选（18787/18788/18789…），远端端口固定写各台机器的 18787。Runner 只接受回环访问，任意本地端口都行。

### 第 3 步 · 网站内

- **步骤1 连接推理服务**：填 服务 IP / 端口 / 模型名 / tokenizer 路径 → 检查连接（自动保存到 Runner）
- **步骤2 选择数据集**：GSM8K / GPQA / AIME2026 已随包携带
- **步骤3 配置参数**：样本数、并发、max_out_len → 开始测试

---
# 备注：
## 下载途径

压缩包/fetch-ascend-bench.sh下载固定地址（下面以压缩包为例）：

| 通道 | 命令 | 特点 |
|---|---|---|
| jsdelivr CDN | `curl -fL https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-web@main/dist/ascend-bench-kit.tar.gz -o k.tar.gz` | 国内快，推荐 |
| GitHub Release | `curl -fL https://github.com/ZYY-ing/ascend-bench-web/releases/latest/download/ascend-bench-kit.tar.gz -o k.tar.gz` | 固定 latest 链接，获取最新代码 |
| raw 直链 | `curl -fL https://raw.githubusercontent.com/ZYY-ing/ascend-bench-web/main/dist/ascend-bench-kit.tar.gz -o k.tar.gz` | 备用 |

>如果想要拉最近更新的工具包，建议用github通道直接下载压缩包并执行setup,因为fetch-ascend-bench.sh内部调用jsdelivr受延迟缓存影响不一定能拉到最新代码。

## 脚本参数说明

### fetch-ascend-bench.sh（f.sh）—— 下载 + 安装

```bash
bash f.sh <测试容器名> <容器内持久化项目目录> [Runner端口,默认18787]
```

| 参数 | 必填 | 说明 |
|---|---|---|
| `<测试容器名>` | 是 | 部署 Runner 的测试容器名（host 网络） |
| `<容器内持久化项目目录>` | 是 | 容器内持久化 RW 挂载的 Linux 绝对路径，如 `/home/aisbench_web` |
| `[Runner端口]` | 否 | Runner 在容器内监听的回环端口，默认 `18787` |

>- 被占用时脚本会报错退出（不杀进程）；在命令最后追加端口号换端口，如 `bash f.sh <容器> <目录> 18788`，隧道同步改为 `-L 18787:127.0.0.1:18788`

### setup.sh —— 只安装（不做任何下载）

```bash
bash setup.sh <测试容器名> <容器内持久化项目目录> [已有ais_bench绝对路径] [Runner端口,默认18787]
```

| 参数 | 必填 | 说明 |
|---|---|---|
| `<测试容器名>` | 是 | 测试容器名 |
| `<容器内持久化项目目录>` | 是 | 容器内持久化 RW 挂载的 Linux 绝对路径 |
| `[已有ais_bench绝对路径]` | 否 | 已有 AISBench 环境时复用（跳过安装）；留空则自动装到 `<项目目录>/bench-venv` |
| `[Runner端口]` | 否 | 默认 `18787` |

---

## 升级到新版本（GitHub 更新后）

**不用删任何文件**。停掉旧 runner，重新下载并重跑安装即可：

```bash
docker exec <测试容器名> pkill -f '[r]unner.py'   # 停掉旧 runner（否则端口被占用会报错）
```
之后执行前面的 **快速开始：第一步**

脚本会自动：备份旧的 scripts/website → 覆盖新文件 → 复用已有的 AISBench 环境（pip 对已装包显示"已满足"，很快）。历史测试记录（`results/jobs/`）保留不删。

只有想彻底重装 AISBench 环境时才手动清：`docker exec <容器> rm -rf <项目目录>/bench-venv`。

---

## 停止 / 启动 / 更新 Runner（原始命令，无脚本）

以下命令都在宿主机执行，`<容器名>`、`<项目目录>` 就是安装时传的那两个，`<端口>` 为runner内端口（默认 `18787`）。

**停止 Runner**

```bash
docker exec <容器名> pkill -f '[r]unner.py'
```

**在指定端口启动 Runner**（会在终端打印「隧道 / 登录 / 步骤」回显，不要加 `-d`）

```bash
docker exec -e ASCEND_BENCH_HOME=<项目目录> -e ASCEND_BENCH_CONTAINER=<容器名> -e ASCEND_BENCH_PORT=<端口> <容器名> bash <项目目录>/scripts/start-runner.sh
```

**验证是否起来（返回 200 即成功）**

```bash
docker exec <容器名> curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<端口>/
```

几种常见情况，各对应上面几条命令：
- **容器之前停了，重新进容器部署**：`docker start <容器名>` 启动容器，再用「在指定端口启动」命令拉起 Runner。文件都在持久化挂载上，不用重装。
- **手动 pkill 过，只想重新拉起**：直接跑「在指定端口启动」命令即可。

---
## 迁移到其他服务器

**不要直接拷贝安装好的文件夹**——bench-venv 里是 editable install + system-site-packages，绑定了原容器的 Python 路径和绝对路径，换个机器会坏。

正确做法：压缩包只下一次，`scp` 到各台宿主机，每台跑一遍 `bash ascend-bench-kit/setup.sh <容器> <目录>`（或f.sh）。

**一般一个网段配置一次就行，网段内机器互联**


---

## 结果与文件

```
<项目目录>/results/jobs/<任务ID>/   config.py / command.txt / execution.log / output/
<项目目录>/logs/runner.log          Runner 日志
<项目目录>/runner-token             网站登录凭据
```

---

## 常见问题

- **步骤1 检查连接失败**：先做前提里两条 curl；IP、模型 id 是 `/v1/models` 返回值；tokenizer 是服务器上的路径
- **网站打不开**：隧道是否保持、Runner 是否在跑（`docker exec <容器> pgrep -f runner.py`）
- **下载卡住**：见「网络环境与代理」
