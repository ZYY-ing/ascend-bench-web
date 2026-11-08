---
name: ascend-bench-deploy
description: 在 Ascend 服务器上自动部署 Ascend Bench Web 评测工作台（容器内 Runner + 网页）。当用户说"装/部署 ascend bench"、"给这台机器装评测工作台"、"装 bench 网站"、或在 Ascend 服务器场景提到 ascend-bench-web / f.sh / setup.sh / Runner 18787 时使用。会先问机器 IP 与容器方案，再自动检测内外网与端口占用，完成下载安装，最后给出 SSH 隧道与 token 步骤。
---

# Ascend Bench 部署（自动安装 Runner）

## 目标

在用户的 Ascend 服务器上装好 Ascend Bench Web 的 Runner（网页评测工作台），并交付"用户自己在电脑上建隧道 + 浏览器登录"的步骤。

**安装完不等于完成。** 必须把隧道命令、token 路径、本地端口建议一起交给用户，否则网站打不开。

## 红线（任何阶段都不能做）

1. **不动 vLLM 推理服务**：不 restart 服务容器、不 `pkill vllm`、不改它的启动命令。
2. **不删用户数据**：不 `docker rm` 容器、不 `rm -rf` 项目目录。
3. **唯一允许重启的进程是 Runner**：`pkill -f '[r]unner.py'`（用中括号写法避免匹配到自身包装进程）。
4. **代理地址 / pip 源不写死**：只从用户当次提供的信息读。
5. **不动用户本机已有的 SSH 隧道 / 进程**：本机端口被占用时只告知并换端口，绝不 kill。
6. **不主动展示登录凭据**：`runner-token` 只给路径，**不要 `cat` 出来贴给用户**；验收只看文件是否存在（`test -f`），不看内容。用户明确要求时才给，并提醒它出现在聊天里就是明文。
7. 破坏性动作（重启、覆盖、删除）先说明再做；只读勘察先做完再问。

---

## 阶段 1 · 连接机器（问第 1 个问题）

发送这段（不要一次性问所有细节）：

> 装 Ascend Bench 需要先连上服务器，请给我：
> 1. 机器 IP
> 2. SSH 用户名（默认 root）和端口（默认 22）；如果用密码或私钥登录，一并说明

拿到后建立连接并确认基础能力：

```bash
ssh -o ConnectTimeout=10 -o BatchMode=yes -p <端口> <用户>@<IP> \
  'hostname; docker version --format "{{.Server.Version}}" || echo NO_DOCKER; python3 -V 2>&1'
```

- `NO_DOCKER` → 提示这台机器不能跑本工具（需要宿主机有 docker），停止。
- 连不上 → 提示检查 IP / 端口 / 密钥，不要反复硬试。

## 阶段 2 · 自动勘察（不做任何改动，一次跑完）

把下面脚本存成文件后 `ssh ... 'bash -s' < recon.sh` 执行（避免多层引号被打碎）：

```bash
echo "== host =="; hostname; date -Is
echo "== containers =="; docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' | head -40
echo "== running bench runners =="
for c in $(docker ps --format '{{.Names}}'); do
  docker exec "$c" pgrep -f '[r]unner.py' >/dev/null 2>&1 && echo "RUNNER_RUNNING $c"
done
echo "== installed bench (mounts with scripts/runner.py) =="
for c in $(docker ps -a --format '{{.Names}}'); do
  for d in $(docker inspect -f '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' "$c" 2>/dev/null); do
    docker exec "$c" test -f "$d/scripts/runner.py" 2>/dev/null && echo "INSTALLED $c $d"
  done
done
echo "== host paths =="; ls -d /home/*/*/scripts/runner.py 2>/dev/null | head
echo "== port 18787 =="; ss -tlnp 2>/dev/null | grep -w 18787 || echo PORT_FREE
echo "== network =="
for u in https://raw.githubusercontent.com/ZYY-ing/ascend-bench-web/main/dist/ascend-bench-kit.tar.gz https://raw.githubusercontent.com/ZYY-ing/ascend-bench-web/main/dist/ascend-bench-kit.tar.gz.sha256; do
  printf '%s ' "$u"; curl -sI -o /dev/null -w '%{http_code}\n' --connect-timeout 6 --noproxy '*' "$u"
done
```

判断规则：

| 结果 | 含义 |
|---|---|
| 任一 URL 返回 `200/302/403` | 能直连外网 → 不需要代理 |
| 两者都是 `000` | 内网 → 必须问代理 |
| `RUNNER_RUNNING <c>` | 这个容器已装且 Runner 在跑，属 B 的"更新分支"，升级前先 `pkill` |
| `INSTALLED <c> <dir>` | 已装过，`<dir>` 就是项目目录 |
| `PORT_FREE` | 远端 Runner 端口可用 |

## 阶段 3 · 汇报 + 问第 2 个问题（一次问清）

把勘察结果压缩成 4~6 行发给用户，然后给选项：

> 已连上 `<IP>`（hostname `<host>`）。勘察结果：
> - 容器 N 个；已装 Ascend Bench：`<容器> → <项目目录>`（没装就写"无"）
> - 网络：外网直连可用 / 内网（需要代理）
> - Runner 端口 18787：空闲 / 被旧 Runner 占用 / 被其他进程占用
>
> 请选装法（回 A / B）：
> **A. 新建专用测试容器** — 需要你提供：容器名（例 `xx_bench_runner`）、镜像（机器上现成镜像名或下载地址）、挂载路径（宿主机路径 ↔ 容器内路径）
> **B. 用现成容器** — 需要你提供：容器名、挂载路径。我会自动检测是否装过 Runner、Runner 进程是否还在，然后拉最新代码部署并启动。
>
> 另外确认：这台机器是内网还是外网？内网请给代理 `IP:端口`（例 `http://<代理IP>:<端口>`，如 `http://1.2.3.4:3128`）。

不要替用户决定 A/B；勘察到"已装"时可以提示"你的机器上已有 Runner，选 B 就能直接更新"，但仍要用户确认。

## 阶段 4 · 按方案准备容器

### A · 新建专用测试容器

1. 确认镜像：`docker images --format '{{.Repository}}:{{.Tag}}' | grep -i <镜像名>`；不存在则 `docker pull <下载地址>`。
2. 以机器上已有的可用测试容器为参照，复制它的设备/驱动挂载，**只加一个持久化目录**：

```bash
docker inspect <参考容器> --format '{{json .HostConfig.Binds}}'   # 参考用，不要照抄全部
docker run -d --name <容器名> --net=host --privileged --shm-size=500g \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
  -v /usr/local/Ascend/driver/lib64:/usr/local/Ascend/driver/lib64:ro \
  -v <宿主机挂载路径>:<容器内挂载路径> \
  <镜像> sleep infinity
docker exec <容器名> bash -c 'python3 -V; curl --version | head -1'
```

3. 必须校验：`NetworkMode=host`、挂载是 `RW=true`、容器内 `python3` + `curl` 可用。

> 容器只需要 host 网络 + 持久化 RW 目录 + python3/curl；Runner 是纯 HTTP 客户端，不需要 CANN 环境变量。

### B · 用现成容器（自动判断装没装过）

先查四件事（只读，一次跑完）：

```bash
docker inspect --format '{{.State.Running}}' <容器名>                      # false → docker start <容器名>
docker inspect --format '{{.HostConfig.NetworkMode}}' <容器名>             # 必须 host
docker exec <容器名> test -f <项目目录>/scripts/runner.py && echo INSTALLED || echo NOT_INSTALLED
docker exec <容器名> pgrep -f '[r]unner.py' >/dev/null && echo RUNNER_ALIVE || echo NO_RUNNER
```

按结果走：

| 情况 | 动作 |
|---|---|
| `NOT_INSTALLED` | 按阶段 5 正常安装 |
| `INSTALLED` + `NO_RUNNER` | 覆盖更新后启动（阶段 5） |
| `INSTALLED` + `RUNNER_ALIVE` | 先 `pkill` 再覆盖更新启动（阶段 5） |
| 容器 `false`（停着） | 先 `docker start`；文件在持久化挂载上不会丢，不用重装 |

覆盖更新会先备份旧 `scripts/website` 到 `<项目目录>/backups/`，`results/jobs/` 历史记录保留。

## 阶段 5 · 安装

**先把远端 Runner 端口的旧占用清掉**（仅限旧 Runner，其他进程不要动）：

```bash
ss -tlnp | grep -w 18787        # 看占用者
docker exec <容器名> pkill -f '[r]unner.py' || true
sleep 2
```

按 [README 方式 B](README.md#快速开始3-步) 下载当前 main 的工具包及校验文件；不要把旧 Release 当作当前 main，也不要用 CDN 下载成功代替版本核验。`setup.sh` 的安装方式和参数不变。

**外网直连**（勘察显示可直连）：

```bash
cd /tmp
curl -fL https://raw.githubusercontent.com/ZYY-ing/ascend-bench-web/main/dist/ascend-bench-kit.tar.gz -o ascend-bench-kit.tar.gz || exit 1
curl -fL https://raw.githubusercontent.com/ZYY-ing/ascend-bench-web/main/dist/ascend-bench-kit.tar.gz.sha256 -o ascend-bench-kit.tar.gz.sha256 || exit 1
sha256sum -c ascend-bench-kit.tar.gz.sha256 || exit 1
tar xzf ascend-bench-kit.tar.gz || exit 1
bash ascend-bench-kit/setup.sh <容器名> <容器内项目目录> "" 18787
```

**内网**（勘察显示直连不通）——环境变量、下载和安装在**同一个 shell** 里：

```bash
export ASCEND_BENCH_PROXY=http://<代理IP:端口>
export ASCEND_BENCH_PIP_INDEX=http://mirrors.tools.huawei.com/pypi/simple
cd /tmp
curl -fL -x "$ASCEND_BENCH_PROXY" \
  https://raw.githubusercontent.com/ZYY-ing/ascend-bench-web/main/dist/ascend-bench-kit.tar.gz -o ascend-bench-kit.tar.gz || exit 1
curl -fL -x "$ASCEND_BENCH_PROXY" \
  https://raw.githubusercontent.com/ZYY-ing/ascend-bench-web/main/dist/ascend-bench-kit.tar.gz.sha256 -o ascend-bench-kit.tar.gz.sha256 || exit 1
sha256sum -c ascend-bench-kit.tar.gz.sha256 || exit 1
tar xzf ascend-bench-kit.tar.gz || exit 1
bash ascend-bench-kit/setup.sh <容器名> <容器内项目目录> "" 18787
```

- 容器内解析不了内网域名（pip 报 `Temporary failure in name resolution`）时，再加
  `export ASCEND_BENCH_EXTRA_HOSTS="<内网源IP> <内网源域名>"`。
- 18787 被**非 Runner** 进程占用时换端口，注意两个脚本的参数位置**不一样**：
  - 用 `f.sh`：`bash f.sh <容器名> <项目目录> 18788`（第 3 个参数就是端口）
  - 用 `setup.sh`：`bash setup.sh <容器名> <项目目录> "" 18788`（第 3 个参数是"已有 ais_bench 路径"，**必须留空**；端口是第 4 个）
  - 交付时把隧道右侧端口同步改成同一个值（18788）。
- 首次安装含 AISBench 依赖（opencv/pyarrow 等，几十 MB），**慢不等于卡住**：看 pip 进度条是否在动。已装过的环境会复用，通常 1 分钟内完成。
- SHA256 不匹配时停止，不安装该包；main 正在更新时可重新成对下载，或将两个 URL 的 `main` 同时改成同一个确认过的 commit。下载报证书错误时配置可信 CA，不以 `-k` 跳过校验。

## 阶段 6 · 验收 + 交付

安装验收（示例使用远端 18787；自定义端口时同步替换）：

```bash
docker exec -w / <容器名> curl --noproxy '*' --fail --silent --show-error --max-time 10 -o /dev/null -w 'site=%{http_code}\n' http://127.0.0.1:18787/
docker exec -w / <容器名> test -s <项目目录>/runner-token
sha256sum ascend-bench-kit/scripts/runner.py ascend-bench-kit/website/config.js
docker exec -w / <容器名> sha256sum <项目目录>/scripts/runner.py <项目目录>/website/config.js
docker exec -w / <容器名> tail -n 15 <项目目录>/logs/runner.log
```

- 要求站点返回 `site=200`、token 文件非空、容器内两份文件各自的 SHA256 与刚解压的对应文件一致。不要再依赖网页 `<small>v...` 文本判断版本。
- 日志应有「Runner 已启动：http://127.0.0.1:<端口>」，且无本次启动的异常堆栈；不要求日志里出现安装命令终端上的隧道交付回显。站点未就绪时查启动日志，不盲目反复重启。
- 安装验收不等于模型测试通过。用户已授权功能测试且服务无其他测试占用时，再从网页连接服务、生成小数据集并提交小批量任务；核对 `config.py`、`command.txt`、`run.sh`、原生结果与结束后空闲状态。不要仅凭 HTTP 200 或退出码 0 宣称所有请求成功，须同时看失败请求数、提示和精度评分/性能表。
- 当前精度为 `all`、性能为 `perf`；`perf + reuse` 保留原生行为。并发在模型配置里，不能要求命令出现 `--batch-size`；retry 原值透传、默认超时不限时，稳态与 pressure 独立。额外参数与限制以 [README](README.md#当前测试逻辑与参数2026-11-08) 为准。
- 日志轮询只显示尾部，检查完整日志应下载导出或读取任务目录的 `execution.log`，不能因网页缺少开头判断源文件丢失。已有实机验证范围见 [验收记录](docs/VERIFICATION.md)；不把历史小批量、配置验证或数据生成结果当成本次全量测试通过。

然后给用户这段（把尖括号换成实际值）：

> 服务器这边装好了（Runner 在 `127.0.0.1:18787`，站点返回 200）。
>
> 接下来在你自己的电脑上（只需一次）：
>
> ```bash
> ssh -N -o ExitOnForwardFailure=yes -L <本地端口>:127.0.0.1:18787 <SSH用户>@<机器IP>
> ```
>
> 然后浏览器打开 `http://127.0.0.1:<本地端口>`，登录凭据在服务器上的 **`<项目目录>/runner-token`**。这是密码，**我不显示内容**，你自己在服务器上读取。
>
> 本地端口怎么定（先看本机有没有隧道；**已有隧道一律不动，只换端口**）：
>
> 1. **本机 18787 的隧道还在，且指向这台机器** → 不用再建，**直接在浏览器打开 `http://127.0.0.1:18787`**。
> 2. **本机 18787 已被占用（指向别的机器或其他程序）** → **不要关闭它**。告诉用户"18787 已被占用"，改用 `18788`：
>    ```bash
>    ssh -N -o ExitOnForwardFailure=yes -L 18788:127.0.0.1:18787 <SSH用户>@<机器IP>
>    ```
>    浏览器打开 `http://127.0.0.1:18788`。仍然被占就依次试 `18789`、`18790`。
>    想确认是谁占：Windows `netstat -ano | findstr :18787`；Linux/Mac `ss -tlnp | grep 18787`（只看，不杀）。
> 3. **没有任何隧道** → 用 `18787`；被别的程序占了就按第 2 条换端口。
>
> 多台机器同时用时，每台本地端口必须不同（18787/18788/18789），远端始终是 18787。
> 刚才若发现**远端** 18787 上有旧 Runner，已停掉并重启到同一端口，隧道按 18787 即可（这是服务器侧，不影响你本机的隧道）。

> 如果 agent 能直接操作你本机的 shell（不是只在服务器上），先按上面三条检查本机端口，再给出唯一结论；否则把这三条连同检查命令原样发给用户。
>
> 登录后按网站三步：步骤1 填服务 IP / 端口 / 模型名 / tokenizer → 检查连接 → 步骤2 选数据集 → 步骤3 参数 → 开始测试。

## 常见问题（按现象定位）

| 现象 | 处理 |
|---|---|
| 安装时下载卡住十几秒后失败重试 | 正常：脚本先直连快速失败再重试/降级；内网请确认已 `export ASCEND_BENCH_PROXY` |
| 拉的还是旧代码 | 按阶段 5 从 GitHub main 直链成对下载工具包和 SHA256 文件并校验；CDN 可能缓存旧包，旧 Release 不保证包含当前 main 修复。安装后比对解压包与容器内源码哈希 |
| pip 很慢 / 长时间不动 | 内网设 `ASCEND_BENCH_PIP_INDEX=http://mirrors.tools.huawei.com/pypi/simple`；pip 已内置 `--timeout 30 --retries 5`，opencv 已钉版本 |
| setup 报「端口已被占用」 | 旧 Runner 还在：`docker exec <容器> pkill -f '[r]unner.py'` 后再装 |
| setup.sh 报 `ais_bench 不存在或不可执行: 18787` | 端口传错位置：`setup.sh` 第 3 个参数是 ais_bench 路径，端口是第 4 个 → `bash setup.sh <容器> <目录> "" 18787` |
| 容器之前停过，文件还在 | `docker start <容器>` 后重跑 `bash f.sh <容器> <目录>`，环境会复用，不用重装 |
| 网站打不开 / 隧道报 Connection refused | 核对隧道右侧端口是否与 Runner 实际端口一致（默认 18787），`ss -tlnp \| grep 18787` 在服务器上确认 |
| 步骤1 检查连接失败 Errno 111 | 端口填错或服务只绑了别的网卡；先 `curl <IP>:<端口>/v1/models` 能通再填 |
| 精度测试报 max_tokens 超限 | `输入 + 最大输出 ≤ 服务端 max-model-len`，把 max_out_len 调小（32768 上下文的机器建议 8192） |

## 附录 · 脚本参数

```bash
# 下载 + 安装（端口是第 3 个参数）
bash f.sh <测试容器名> <容器内持久化项目目录> [Runner端口,默认18787]

# 只安装（第 3 个参数是已有 ais_bench 绝对路径，没有就写 ""；端口是第 4 个）
bash setup.sh <测试容器名> <容器内持久化项目目录> ["已有ais_bench路径"或""] [Runner端口,默认18787]
```

> ⚠️ **两个脚本的端口位置不同，最容易搞错**：`f.sh` 端口是第 3 个；`setup.sh` 端口是第 4 个，第 3 个是 ais_bench 路径。
> 把端口写成 `setup.sh <容器> <目录> 18787` 会被当成 ais_bench 路径，直接报 `ais_bench 不存在或不可执行: 18787`。setup.sh 换端口的正确写法是 `bash setup.sh <容器> <目录> "" 18787`。

| 环境变量 | 用途 |
|---|---|
| `ASCEND_BENCH_PROXY` | 内网代理，curl 下载与 pip 安装共用 |
| `ASCEND_BENCH_PIP_INDEX` | pip 源，默认阿里云；内网固定 `http://mirrors.tools.huawei.com/pypi/simple` |
| `ASCEND_BENCH_EXTRA_HOSTS` | `"IP 域名"`，写入容器 `/etc/hosts`，容器解析不了内网域名时用 |

测试记录归档在 `<项目目录>/results/jobs/<任务ID>/`，每条任务独立目录，不会互相覆盖。
