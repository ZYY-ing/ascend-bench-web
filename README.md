# Ascend Bench Web

给**已经拉起并验证过的 vLLM 服务**（Ascend 服务器）提供的网页版模型评测工作台。浏览器操作，精度 / 性能测试全程无需改代码。

公开发布与敏感文件边界见 [SECURITY.md](SECURITY.md)。

> ## 🚀 **想省事？把这个喂给 AI agent，让它自动装好**
>
> 把仓库根目录的 **[`SKILL.md`](SKILL.md)** 直接贴给你的 AI agent（或告诉它"按 SKILL.md 装 ascend-bench"），它会自动完成：问你机器 IP 和容器方案 → 检测内外网与端口占用 → 下载安装 → 起 Runner → 把 SSH 隧道命令和 token 路径交给你。
>
> **手动安装**按下面的步骤走即可。

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

**vLLM 服务容器**（起服务的那个容器）需要：模型权重目录只读挂载即可（如 `/mnt/weight/...`）。这是起服务时本来就挂好的，**不需要为本工具额外挂任何东西**。

> 说明：之前遇到的"重启 vLLM 后挂载"问题，不是加了新挂载——是我把项目目录 `rm -rf` 了但容器还 bind-mount 着它，导致挂载指向已删除的旧目录；`docker restart` 让容器重新解析了已有的 bind-mount 而已。

---

## 快速开始（3 步）

### 第 1 步 · 服务器宿主机（下载 + 安装）

以下命令在服务器宿主机的 **Bash** 终端执行，不是在 Windows PowerShell 中执行。宿主机需要 `curl`、`python3`、`tar`、`sha256sum`、`bash` 和 Docker。

**每次安装、以后更新都使用同样的命令，不需要填写、修改或记录提交号。** 脚本自动向 GitHub 查询 main 最新版本，再下载并校验对应安装包。需要代理时，先看下文[内网配置](#网络环境与代理两种环境脚本如下)。

**方式 A · 自动下载最新版本并安装（推荐新安装）**：

```bash
curl -fL -H 'Cache-Control: no-cache' \
  "https://raw.githubusercontent.com/ZYY-ing/ascend-bench-web/main/fetch-ascend-bench.sh?fresh=$(date +%s)" -o f.sh &&
bash f.sh <测试容器名> <容器内持久化项目目录>
```

只替换容器名和持久化目录即可。可选第 3 个参数为 Runner 端口，例如 `bash f.sh <容器名> <项目目录> 18788`。请保留 `&&`：如果脚本下载失败，就不会接着运行以前残留的旧脚本。

这两条命令是长期通用入口，后续仓库更新仍执行相同命令。URL 中的 `$(date +%s)` 自动生成请求时间，用于避开脚本入口缓存，也不需要用户手动改。

**方式 B · 只下载最新包，不安装（推荐更新已有 Runner / 离线转运）**：

```bash
curl -fL -H 'Cache-Control: no-cache' \
  "https://raw.githubusercontent.com/ZYY-ing/ascend-bench-web/main/fetch-ascend-bench.sh?fresh=$(date +%s)" -o f.sh &&
bash f.sh --download-only ./ascend-bench-download
```

脚本自动查询最新版本、下载并校验，将安装包、SHA256 校验文件和自动生成的版本记录保存到 `./ascend-bench-download/`。这个模式不执行安装、不启动或停止容器及 Runner。

下载成功后，首次安装可继续：

```bash
cd ascend-bench-download
sha256sum -c ascend-bench-kit.tar.gz.sha256
tar xzf ascend-bench-kit.tar.gz
bash ascend-bench-kit/setup.sh <测试容器名> <容器内持久化项目目录>
```

已有 Runner 时，先看到 `ascend-bench-kit.tar.gz: OK`，再按下文[升级说明](#升级到新版本github-更新后)确认空闲并停止对应 Runner，最后执行 `setup.sh`。下载或校验失败时停止，不要继续使用旧文件。

脚本内部会自动取得 GitHub 的版本标识，让脚本运行期间的包和校验文件保持一致。**这是内部核对步骤，不是用户要填写的参数。** 一次下载开始后若 main 又更新，下次执行原命令即可取得新版本。

### 第 2 步 · 你的电脑（建隧道 + 登录）

```bash
ssh -N -o ExitOnForwardFailure=yes -L 18787:127.0.0.1:18787 <SSH用户>@<服务器IP>
```

浏览器打开 http://127.0.0.1:18787，粘贴 `<项目目录>/runner-token` 里的凭据登录。

### 第 3 步 · 网站内

- **步骤1 连接推理服务**：填 服务 IP / 端口 / 模型名 / tokenizer 路径 → 检查连接（自动保存到 Runner）
- **步骤2 选择数据集**：GSM8K / GPQA / AIME2026 已随包携带
- **步骤3 配置参数**：样本数、并发、max_out_len → 开始测试

---

## 两个脚本的区别

| 脚本 | 作用 |
|---|---|
| `fetch-ascend-bench.sh` | **下载 + 安装**。先下载压缩包、解压，再调用 setup.sh |
| `setup.sh` | **只安装**。不做任何下载，只做环境检查、拷文件、建 AISBench 环境、起 Runner |

所以：**有网直接跑方式 A（fetch）**；已经有解压好的 `ascend-bench-kit/` 目录时，只用 `bash ascend-bench-kit/setup.sh <容器> <目录>` 即可，不需要 fetch。

---

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

环境变量（可选，都不设即外网行为）：

| 变量 | 说明 |
|---|---|
| `ASCEND_BENCH_PROXY` | 内网下载代理，如 `http://192.0.2.20:3128`（curl 下载 + pip 安装共用） |
| `ASCEND_BENCH_PIP_INDEX` | pip 源，默认 `https://mirrors.aliyun.com/pypi/simple` |
| `ASCEND_BENCH_EXTRA_HOSTS` | 可选，格式 `"IP 域名"`，写入容器 /etc/hosts（解析不了内网源域名时） |

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

环境变量：同 fetch-ascend-bench.sh（`ASCEND_BENCH_PROXY` / `ASCEND_BENCH_PIP_INDEX` / `ASCEND_BENCH_EXTRA_HOSTS`）。

---

## 怎么在服务器上下载这个仓库的文件

- **普通用户安装 / 更新**：使用上面的方式 A 或 B，始终是同样的命令，自动下载 GitHub main 最新版。
- **浏览或下载完整源码**：[GitHub 当前代码](https://github.com/ZYY-ing/ascend-bench-web)、[下载 main 源码 ZIP](https://github.com/ZYY-ing/ascend-bench-web/archive/refs/heads/main.zip)。解压源码 ZIP 后可在目录中运行 `bash fetch-ascend-bench.sh <容器名> <项目目录>`。
- **习惯使用 Git**：也可以克隆 main；已有克隆以后先 `git pull --ff-only`，再运行下载脚本。

```bash
git clone --depth 1 --branch main https://github.com/ZYY-ing/ascend-bench-web.git
cd ascend-bench-web
bash fetch-ascend-bench.sh <测试容器名> <项目目录>
```

不再推荐 `CDN@main` 或旧 Release 的 latest 下载入口：缓存分支别名可能返回旧包，下载成功并不代表最新。新版脚本自动确认 GitHub main，再按 GitHub raw → GitHub 源码 API → 固定版本 CDN 的顺序下载，SHA256 校验通过才安装。版本查询默认使用 GitHub API；若 API 不可用且宿主机有 Git，会自动尝试 Git 查询。两者都失败时停止，不退回缓存旧版。

### 网络环境与代理（两种环境，脚本如下）

内外网使用同一脚本，安装参数不变。区别是下载和 pip 使用的网络配置；环境变量、下载脚本和安装命令在同一个 Bash 终端中执行。

**情况一 · 外网直连**：直接复制快速开始中的方式 A 或 B，无需填版本号或代理。

**情况二 · 内网代理**：先设置实际代理和可达的 pip 源，再下载、执行脚本：

```bash
export ASCEND_BENCH_PROXY='http://<代理IP>:<端口>'
export ASCEND_BENCH_PIP_INDEX='http://mirrors.tools.huawei.com/pypi/simple'
# 仅在容器无法解析包源域名时设置，IP 和域名按实际填写：
# export ASCEND_BENCH_EXTRA_HOSTS='<内网源IP> <内网源域名>'

curl -fL -x "$ASCEND_BENCH_PROXY" -k -H 'Cache-Control: no-cache' \
  "https://raw.githubusercontent.com/ZYY-ing/ascend-bench-web/main/fetch-ascend-bench.sh?fresh=$(date +%s)" -o f.sh &&
bash f.sh <测试容器名> <容器内持久化项目目录>
```

只下载不安装时，将最后一行换成 `bash f.sh --download-only ./ascend-bench-download`。首次下载脚本也必须显式传入代理；普通 curl 不会自动读取 `ASCEND_BENCH_PROXY` 这个自定义变量。

- 下载脚本先尝试直连，再尝试配置的代理；不会把代理地址打印到下载日志。
- `ASCEND_BENCH_PIP_INDEX` 只控制容器安装依赖的 pip 源，不能代替访问 GitHub 的代理；未设置时沿用阿里云默认源。镜像域名保留，代理 IP 由用户自己填写。
- 代理下载沿用原来的 `-k` 兼容行为，会跳过证书校验。已有可信 CA 时可移除入口命令的 `-k` 并配置 `CURL_CA_BUNDLE`；脚本内代理分支的 curl 参数也需同步调整。pip 与 curl 是两段独立网络设置。
- 版本查询失败或 API 限流时，先检查网络/代理，稍后重试同一命令；不需要改 README 或手填一串版本数字。

**离线转运**：在具备 Bash、Python 3、curl、tar、sha256sum 的联网电脑运行方式 B，把整个 `ascend-bench-download` 目录复制到服务器。服务器重新校验 SHA256，通过后解压并运行 `setup.sh`。容器中的 AISBench 依赖仍需可达包源，或预先备齐匹配的离线环境；仅有安装包不代表所有依赖已经齐备。

### 怎么确认安装的是本次下载的代码

脚本会自动打印所获取的版本和 SHA256 校验结果，版本信息只是供排查，不需要用户填写。安装后可比较刚解压的包与容器内文件：

```bash
sha256sum ascend-bench-kit/scripts/runner.py ascend-bench-kit/website/config.js
docker exec <测试容器名> sha256sum <项目目录>/scripts/runner.py <项目目录>/website/config.js
```

同名文件的哈希应一致。不要只凭网页静态版本文字、下载返回 200 或文件已存在判断最新。仅文档变化的提交可能复用相同运行包，这是正常的。

---

## 升级到新版本（GitHub 更新后）

更新已有 Runner 推荐使用方式 B：**先用方式 B 自动下载、校验并解压最新包，再安排对应 Runner 的空闲更新窗口**。不要先停 Runner 再等待网络下载。

确认目标 Runner 已空闲、任务进程结束，并核对其 PID、命令行路径和工作目录属于本项目，然后只停止这个 Runner：

```bash
docker exec <测试容器名> kill -TERM <已核验的Runner_PID>
# 确认对应端口释放后，使用已经下载并校验的包：
bash ascend-bench-kit/setup.sh <测试容器名> <项目目录>
```

不要停止其他 Runner，也不需要重启容器或 vLLM。脚本会备份原 `scripts/website`、更新项目文件、复用有效虚拟环境并校验/补齐依赖；`results/jobs/` 历史记录保留。单机版安装后需要重新填写并检查服务连接，不能把文件更新完成当作模型测试已通过。

不用删除安装目录或虚拟环境来完成普通更新。首次安装或依赖缺失时，安装耗时仍取决于包源、代理与缓存。

## 迁移到其他服务器

**不要直接拷贝安装好的文件夹**——bench-venv 里是 editable install + system-site-packages，绑定了原容器的 Python 路径和绝对路径，换个机器会坏。

正确做法：压缩包只下一次，`scp` 到各台宿主机，每台跑一遍 `bash ascend-bench-kit/setup.sh <容器> <目录>`（或方式 A 的 fetch）。venv 每台单独装（约 3~5 分钟，匹配各自容器的 Python），网站步骤1 按各台机器的服务 IP 重新填写即可。

---

## Runner 端口（默认 18787）

- 默认监听容器内 `127.0.0.1:18787`（仅回环，经 SSH 隧道访问）
- 被占用时脚本会报错退出（不杀进程）；在命令最后追加端口号换端口，如 `bash f.sh <容器> <目录> 18788`，隧道同步改为 `-L 18787:127.0.0.1:18788`

## 多台机器同时用

每台机器映射**一个不同的本地端口**建隧道，浏览器各开一个标签页，登录态互不干扰（cookie 按本地端口隔离）：

```bash
ssh -N -L 18787:127.0.0.1:18787 <用户>@<机器1>   # 标签页1: http://127.0.0.1:18787
ssh -N -L 18788:127.0.0.1:18787 <用户>@<机器2>   # 标签页2: http://127.0.0.1:18788
ssh -N -L 18789:127.0.0.1:18787 <用户>@<机器3>   # 标签页3: http://127.0.0.1:18789
```

> 本地端口随便选（18787/18788/18789…），远端端口固定写各台机器的 18787。Runner 只接受回环访问，任意本地端口都行。

## 停止 / 启动 / 更新 Runner（原始命令，无脚本）

以下命令都在宿主机执行，`<容器名>`、`<项目目录>` 就是安装时传的那两个，`<端口>` 换成你要的（默认 `18787`）。

**停止 Runner**（先确认空闲，并核对 PID 的命令行与工作目录属于本项目）

```bash
docker exec <容器名> kill -TERM <已核验的Runner_PID>
```

**在指定端口启动 Runner**（会在终端打印「隧道 / 登录 / 步骤」回显，不要加 `-d`）

```bash
docker exec -e ASCEND_BENCH_HOME=<项目目录> -e ASCEND_BENCH_CONTAINER=<容器名> -e ASCEND_BENCH_PORT=<端口> <容器名> bash <项目目录>/scripts/start-runner.sh
```

**验证是否起来（返回 200 即成功）**

```bash
docker exec <容器名> curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<端口>/
```

三种常见情况，各对应上面几条命令：

- **代码更新了，拉最新代码重新部署**：先按方式 B 自动下载、校验新包，再在空闲窗口停止已核验的 Runner，执行 `setup.sh`（见「升级到新版本」）。
- **容器之前停了，重新进容器部署**：`docker start <容器名>` 启动容器，再用「在指定端口启动」命令拉起 Runner。文件都在持久化挂载上，不用重装。
- **手动 pkill 过，只想重新拉起**：直接跑「在指定端口启动」命令即可。

## 容器删除/停止后的恢复（不用重装）

安装目录在**持久化挂载**上（setup.sh 强制要求），所以容器被删/停后文件和环境都还在，只是 Runner 进程没了。恢复只需两步：

```bash
# 1. 重建/重启容器（保留原来的项目目录挂载，同一个镜像）
# 2. 重跑一次安装脚本（秒级：检测到已有 AISBench 环境会自动跳过安装，只更新文件并拉起 Runner）
bash ascend-bench-kit/setup.sh <容器名> <项目目录>
```

项目目录被删了才需要真正重装。换**不同镜像**的容器时（Python 版本变了），先清掉旧 venv 再重装：`docker exec <新容器> rm -rf <项目目录>/bench-venv`。

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
- **端口占用报错**：
  OSError: [Errno 98] Address already in use
  
  容器内 18787 端口已被占用（可能有其他 Runner 或服务）。如果确定是你之前的容器可停掉旧 Runner， 否则换端口重装。

  执行docker exec <测试容器名> pkill -f '[r]unner.py'停掉之后重新执行f.sh或者setup.sh
  
- **网站打不开**：隧道是否保持、Runner 是否在跑（`docker exec <容器> pgrep -f runner.py`）
- **下载卡住**：见「网络环境与代理」

## 源码维护与本地验证

可编辑 Runner 源码在 `runner-src/scripts/`、`runner-src/website/`；`runner-src/setup.sh` 保留原安装实现。固定 AISBench 源码与基础数据仍随 `dist/ascend-bench-kit.tar.gz` 分发。修改测试逻辑后重新构建再安装：

```bash
python tools/build_kit.py
python -m unittest discover -s tests -t . -p 'test_*.py'
# Node.js 仅用于开发验证，不是 Runner 运行依赖：
node tests/test_final_controls.cjs
node tests/test_log_display.cjs
```

构建不在线抓取新版 AISBench，附带 SHA256 文件；少量进程启动兼容处理只作用本次客户端，不修改 vLLM、驱动或 Docker 安全策略。实机小批量、长数据生成、故障模拟及安装环境前提见 [验收记录](docs/VERIFICATION.md)，配置通过不等于所有高并发或长输出规模都已跑完。
