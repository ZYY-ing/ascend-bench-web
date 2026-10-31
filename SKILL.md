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
6. 破坏性动作（重启、覆盖、删除）先说明再做；只读勘察先做完再问。

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
for u in https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-web@main/dist/ascend-bench-kit.tar.gz https://api.github.com/; do
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
> 另外确认：这台机器是内网还是外网？内网请给代理 `IP:端口`（例 `141.2.239.180:3128`）。

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

**外网直连**（勘察显示可直连）：

```bash
cd /tmp
curl -fL https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-web@main/fetch-ascend-bench.sh -o f.sh
bash f.sh <容器名> <容器内项目目录> 18787
```

**内网**（勘察显示直连不通）——三个变量 + 两条命令必须在**同一个 shell** 里：

```bash
export ASCEND_BENCH_PROXY=http://<代理IP:端口>
export ASCEND_BENCH_PIP_INDEX=http://mirrors.tools.huawei.com/pypi/simple
cd /tmp
curl -fL -x "$ASCEND_BENCH_PROXY" -k \
  https://github.com/ZYY-ing/ascend-bench-web/releases/latest/download/fetch-ascend-bench.sh -o f.sh
bash f.sh <容器名> <容器内项目目录> 18787
```

- 容器内解析不了内网域名（pip 报 `Temporary failure in name resolution`）时，再加
  `export ASCEND_BENCH_EXTRA_HOSTS="<内网源IP> <内网源域名>"`。
- 18787 被**非 Runner** 进程占用时，改用 `18788` 安装（第三个参数），并在交付时把隧道右侧同步改成 18788。
- 首次安装含 AISBench 依赖（opencv/pyarrow 等，几十 MB），**慢不等于卡住**：看 pip 进度条是否在动。已装过的环境会复用，通常 1 分钟内完成。

## 阶段 6 · 验收 + 交付

验收（三条都要过）：

```bash
docker exec <容器名> curl -s -o /dev/null -w 'site=%{http_code}\n' http://127.0.0.1:18787/
docker exec <容器名> grep -o 'small>v[0-9.]*' <项目目录>/website/index.html | tail -1
docker exec <容器名> tail -n 15 <项目目录>/logs/runner.log
```

- `site=200` 才算起成功；不是 200 → `tail -50 logs/runner.log` 找原因，**不要盲目反复重启**。
- 日志里应能看到「Runner 启动中 / 本机隧道 / 打开」的启动回显块。

然后给用户这段（把尖括号换成实际值）：

> 服务器这边装好了（Runner 在 `127.0.0.1:18787`，站点返回 200）。
>
> 接下来在你自己的电脑上（只需一次）：
>
> ```bash
> ssh -N -o ExitOnForwardFailure=yes -L <本地端口>:127.0.0.1:18787 <SSH用户>@<机器IP>
> ```
>
> 然后浏览器打开 `http://127.0.0.1:<本地端口>`，用这个 token 登录：
> 服务器上执行 `docker exec <容器名> cat <项目目录>/runner-token` 取值。
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
| 拉的还是旧代码 | jsdelivr `@main` 有缓存（约 12 小时）。改用 Release 直链 `.../releases/latest/download/ascend-bench-kit.tar.gz`，或对 `@main` 路径执行 `curl https://purge.jsdelivr.net/gh/ZYY-ing/ascend-bench-web@main/dist/ascend-bench-kit.tar.gz`（GET，不是 POST） |
| pip 很慢 / 长时间不动 | 内网设 `ASCEND_BENCH_PIP_INDEX=http://mirrors.tools.huawei.com/pypi/simple`；pip 已内置 `--timeout 30 --retries 5`，opencv 已钉版本 |
| setup 报「端口已被占用」 | 旧 Runner 还在：`docker exec <容器> pkill -f '[r]unner.py'` 后再装 |
| 容器之前停过，文件还在 | `docker start <容器>` 后重跑 `bash f.sh <容器> <目录>`，环境会复用，不用重装 |
| 网站打不开 / 隧道报 Connection refused | 核对隧道右侧端口是否与 Runner 实际端口一致（默认 18787），`ss -tlnp \| grep 18787` 在服务器上确认 |
| 步骤1 检查连接失败 Errno 111 | 端口填错或服务只绑了别的网卡；先 `curl <IP>:<端口>/v1/models` 能通再填 |
| 精度测试报 max_tokens 超限 | `输入 + 最大输出 ≤ 服务端 max-model-len`，把 max_out_len 调小（32768 上下文的机器建议 8192） |

## 附录 · 脚本参数

```bash
bash f.sh <测试容器名> <容器内持久化项目目录> [Runner端口,默认18787]      # 下载 + 安装
bash setup.sh <测试容器名> <容器内持久化项目目录> [已有ais_bench路径] [Runner端口]  # 只安装
```

| 环境变量 | 用途 |
|---|---|
| `ASCEND_BENCH_PROXY` | 内网代理，curl 下载与 pip 安装共用 |
| `ASCEND_BENCH_PIP_INDEX` | pip 源，默认阿里云；内网固定 `http://mirrors.tools.huawei.com/pypi/simple` |
| `ASCEND_BENCH_EXTRA_HOSTS` | `"IP 域名"`，写入容器 `/etc/hosts`，容器解析不了内网域名时用 |

测试记录归档在 `<项目目录>/results/jobs/<任务ID>/`，每条任务独立目录，不会互相覆盖。
