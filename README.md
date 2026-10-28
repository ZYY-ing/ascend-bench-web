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

**vLLM 服务容器**（起服务的那个容器）需要：模型权重目录只读挂载即可（如 `/mnt/weight/...`）。这是起服务时本来就挂好的，**不需要为本工具额外挂任何东西**。

> 说明：之前遇到的"重启 vLLM 后挂载"问题，不是加了新挂载——是我把项目目录 `rm -rf` 了但容器还 bind-mount 着它，导致挂载指向已删除的旧目录；`docker restart` 让容器重新解析了已有的 bind-mount 而已。

---

## 快速开始（3 步）

### 第 1 步 · 服务器宿主机（下载 + 安装）

**方式 A · 一键（推荐）**：

```bash
curl -fL https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-web@main/fetch-ascend-bench.sh -o f.sh
bash f.sh <测试容器名> <容器内持久化项目目录>
```

**方式 B · 手动（先下压缩包再装）**：

```bash
curl -fL https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-web@main/dist/ascend-bench-kit.tar.gz -o ascend-bench-kit.tar.gz
tar xzf ascend-bench-kit.tar.gz
bash ascend-bench-kit/setup.sh <测试容器名> <容器内持久化项目目录>
```

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

## 怎么在服务器上下载这个仓库的文件

压缩包固定地址（任选其一，都是同一份文件）：

| 通道 | 命令 | 特点 |
|---|---|---|
| jsdelivr CDN | `curl -fL https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-web@main/dist/ascend-bench-kit.tar.gz -o k.tar.gz` | 国内快，推荐 |
| GitHub Release | `curl -fL https://github.com/ZYY-ing/ascend-bench-web/releases/latest/download/ascend-bench-kit.tar.gz -o k.tar.gz` | 固定 latest 链接 |
| raw 直链 | `curl -fL https://raw.githubusercontent.com/ZYY-ing/ascend-bench-web/main/dist/ascend-bench-kit.tar.gz -o k.tar.gz` | 备用 |

### 网络环境与代理（两种环境都支持）

脚本会自动区分外网/内网，通过两个环境变量适配：

| 环境 | 需要做的 | 说明 |
|---|---|---|
| **外网直连**（普通服务器） | 什么都不用设 | 默认 jsdelivr CDN + 阿里云 pip 源 |
| **内网代理**（华为内网等） | 设下面两个变量 | 下载走代理，pip 走内网源 |

内网代理环境，在安装前先 `export`（可写进 `.bashrc`）：

```bash
export ASCEND_BENCH_DOWNLOAD_PROXY=http://<代理IP:端口>   # 例 http://141.2.239.180:3128，外网下载走它
export ASCEND_BENCH_PIP_INDEX=http://<内网pip源>/simple    # 例 http://mirrors.tools.huawei.com/pypi/simple，pip 走内网源
```

变量说明：

- `ASCEND_BENCH_DOWNLOAD_PROXY`：下载工具包时的代理。设了就走 `-x <代理> -k`（`-k` 跳过代理中间人证书，netentsec 类会拦 SSL）；不设就 `--noproxy '*'` 直连，自动绕开 shell 里可能失效的 `http_proxy` 变量。
- `ASCEND_BENCH_PIP_INDEX`：pip 源。默认阿里云；内网环境换成华为内网源（`http://` 源会自动加 `trusted-host`）。pip 统一带 `timeout=30`，不再死等。

> 排查口诀：下载卡住 → 先 `env | grep -i proxy` 看有没有打架的代理变量；外网直连超时 → 设 `ASCEND_BENCH_DOWNLOAD_PROXY` 走代理；pip 慢 → 设 `ASCEND_BENCH_PIP_INDEX` 走内网源。


---

## 升级到新版本（GitHub 更新后）

**不用删任何文件**。停掉旧 runner，重新下载并重跑安装即可：

```bash
docker exec <测试容器名> pkill -f '[r]unner.py'   # 停掉旧 runner（否则端口被占用会报错）
curl -fL https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-web@main/fetch-ascend-bench.sh -o f.sh
bash f.sh <测试容器名> <项目目录>
```

脚本会自动：备份旧的 scripts/website → 覆盖新文件 → 复用已有的 AISBench 环境（pip 对已装包显示"已满足"，很快）。历史测试记录（`results/jobs/`）保留不删。

只有想彻底重装 AISBench 环境时才手动清：`docker exec <容器> rm -rf <项目目录>/bench-venv`。

## 迁移到其他服务器

**不要直接拷贝安装好的文件夹**——bench-venv 里是 editable install + system-site-packages，绑定了原容器的 Python 路径和绝对路径，换个机器会坏。

正确做法：压缩包只下一次，`scp` 到各台宿主机，每台跑一遍 `bash ascend-bench-kit/setup.sh <容器> <目录>`（或方式 A 的 fetch）。venv 每台单独装（约 3~5 分钟，匹配各自容器的 Python），网站步骤1 按各台机器的服务 IP 重新填写即可。

---

## Runner 端口（默认 18787）

- 默认监听容器内 `127.0.0.1:18787`（仅回环，经 SSH 隧道访问）
- 被占用时脚本会报错退出（不杀进程）；在命令最后追加端口号换端口，如 `bash f.sh <容器> <目录> 18788`，隧道同步改为 `-L 18787:127.0.0.1:18788`

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
