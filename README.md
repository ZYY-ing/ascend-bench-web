# ascend-bench-toolkit

Ascend Bench 模型评测工作台部署工具包：给**已经拉起并验证过的 vLLM 服务**（Ascend 服务器）提供网页版精度 / 性能评测。浏览器操作，全程无需改代码。

## 前提

1. vLLM 服务已成功拉起，且在服务器上以下两条命令均返回正常：

   ```bash
   curl http://<服务IP>:<端口>/health
   curl http://<服务IP>:<端口>/v1/models
   ```

2. 测试容器：**host 网络**；有一个**持久化 RW 挂载**的项目目录（容器内可见）；容器内有 python3 和 curl。

## 快速开始（3 步）

### 第 1 步 · 服务器宿主机（一条命令：自动下载 + 安装 + 启动）

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-toolkit@main/fetch-ascend-bench.sh -o f.sh
bash f.sh <测试容器名> <容器内持久化项目目录>
```

下载约 16 秒；首次安装会创建 AISBench 环境，约几分钟（需要访问 pip 镜像）。完成后脚本会打印**隧道命令、网站地址和 token 位置**。

### 第 2 步 · 你的电脑（建立 SSH 隧道并登录）

```bash
ssh -N -o ExitOnForwardFailure=yes -L 18787:127.0.0.1:18787 <SSH用户>@<服务器IP>
```

保持隧道打开，浏览器访问 http://127.0.0.1:18787 ，粘贴 `<项目目录>/runner-token` 里的凭据登录。

### 第 3 步 · 网站内（3 个面板）

- **步骤1 · 连接推理服务**：填 服务 IP / 端口 / 模型名（/v1/models 返回值）/ tokenizer 路径 → 点「检查连接」——通过后自动保存到 Runner
- **步骤2 · 选择数据集**：GSM8K / AIME2026 已随包携带；GPQA 为授权数据，把 `gpqa_diamond.csv` 放入 `<项目目录>/datasets/gpqa/` 后点「重新检查」
- **步骤3 · 配置测试参数**：小批量验收建议 样本 4、并发 1、max_out_len ≥2048（思考型模型）→「开始真实测试」

切换测试目标：改步骤1 面板的服务信息 → 重新点「检查连接」，无需改服务器文件。

## 工具包下载方式（不依赖任何特定服务器）

| 通道 | 地址 |
|---|---|
| jsdelivr CDN（国内快，约 16 秒） | `https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-toolkit@main/dist/ascend-bench-kit.tar.gz` |
| GitHub Release（固定 latest 链接） | `https://github.com/ZYY-ing/ascend-bench-toolkit/releases/latest/download/ascend-bench-kit.tar.gz` |
| 一键安装脚本 | `https://cdn.jsdelivr.net/gh/ZYY-ing/ascend-bench-toolkit@main/fetch-ascend-bench.sh` |

fetch 脚本自动降级：jsdelivr CDN → GitHub API 资产端点 → 内网镜像（`http://192.168.13.198:8001/`），全部失败才报错。

## 端口说明

- Runner 默认监听**容器内 127.0.0.1:18787**（仅回环，只能通过 SSH 隧道访问，不对外暴露）
- **18787 不是写死的**：安装时检测到端口被占用会明确报错退出（绝不杀其他进程），此时在命令最后追加端口号即可更换，例如：

  ```bash
  bash f.sh <测试容器名> <项目目录> 18788
  ```

  隧道命令同步改为：`ssh -N -L 18787:127.0.0.1:18788 <用户>@<服务器IP>`（本地端口随意，远端端口写实际值）

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

## 常见问题

- **步骤1 检查连接失败**：先做前提里的两条 curl；确认 IP、模型 id 是 `/v1/models` 返回值；tokenizer 路径是**服务器上的路径**（不是电脑路径）
- **网站打不开**：检查隧道是否保持、Runner 是否在跑：`docker exec <容器> pgrep -f runner.py`，日志：`docker exec <容器> tail -20 <项目目录>/logs/runner.log`
- **端口占用**：见「端口说明」，换端口重装
- **GPQA 未就绪**：授权数据不随包分发，自备 `gpqa_diamond.csv` 放入指定目录后重新检查

## 仓库内容

- `fetch-ascend-bench.sh` — 一键取包安装脚本
- `dist/ascend-bench-kit.tar.gz` — 部署工具包（网站 + Runner + AISBench 源码 + GSM8K/AIME2026 数据集）
- GitHub Release 提供同内容的版本化资产
