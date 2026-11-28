# DARKIN — AI 自主渗透测试系统

从外网侦察到内网纵深的自主渗透平台。给定目标后由 AI Agent 自行完成
侦察 → 攻击链规划 → 漏洞验证 → 立足点获取 → 内网测绘 → 横向 → 提权 → 收口，
人只在危险操作上被询问（审批门）。

**下载任意一个平台的压缩包，解压即完整环境**：程序本体、红队知识库
（CVE 库 + POC + 战法）、工具集（nuclei/fscan/gogo/chisel 等）、
nuclei 模板（1.5 万+）、skills 库、部署脚本与文档全部在包内。

---

## 最新版本 v0.8.1 下载

| 平台 | 文件 | 适用 |
| --- | --- | --- |
| Windows | `darkin-0.8.1-windows-amd64.zip` | Windows 10/11 x64、Server 2019+ |
| Linux | `darkin-0.8.1-linux-amd64.zip` | 绝大多数 VPS / 服务器 |
| Linux ARM | `darkin-0.8.1-linux-arm64.zip` | ARM 云服务器、树莓派等 |
| macOS Apple Silicon | `darkin-0.8.1-macos-arm64.zip` | M1/M2/M3/M4 |
| macOS Intel | `darkin-0.8.1-macos-amd64.zip` | 2020 年前的 Intel Mac |

校验：下载后比对 `SHA256SUMS`。

> macOS Intel 包不含 `data/tools` 扫描器二进制（上游未发布该平台版本），
> 其余内容一致，可自行放入 x86_64 工具。

---

## 获取安装包（三选一）

**方式一：一键脚本（推荐）** —— 自动识别系统/架构，下载 + 校验 + 解压 + 安装：

```bash
curl -fsSL https://raw.githubusercontent.com/jianmo0x00/darkin-releases/main/install.sh | sudo bash
```

**方式二：GitHub 访问不畅时** —— 用 jsDelivr 加速获取脚本（国内通常可用）：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/jianmo0x00/darkin-releases@main/install.sh | sudo bash
```

一键脚本内部对安装包下载同样做了多源回退（自建镜像 → GitHub → 国内加速代理）。
有自建镜像时可指定：`DARKIN_DL_BASE=https://你的镜像路径`。

**方式三：手动离线安装** —— 在本页下方 Assets 下载对应平台的 zip（可通过任意
渠道传输），上传服务器后：

```bash
unzip darkin-0.8.1-linux-amd64.zip
cd darkin-0.8.1-linux-amd64
chmod +x *.sh darkin
sudo ./install-deps.sh
```

校验：比对本页 Assets 里的 `SHA256SUMS`。

---

## 安装

**不需要 Go / Node / 源码编译** —— 二进制和前端都在包里。
唯一必须自己准备的是 **PostgreSQL 16 或 18**（本机 / 远程 / 容器均可），
外加一个 LLM API Key（进入面板后填）。

### Linux

```bash
unzip darkin-0.8.1-linux-amd64.zip
cd darkin-0.8.1-linux-amd64
chmod +x *.sh darkin
./install-deps.sh    # 一条命令完成安装 + 启动
```

`install-deps.sh` 是交互式一键安装：安装并启动 PostgreSQL、创建 `artex`
数据库、准备 Python 工具环境（impacket/sqlmap/pypykatz 等）、安装 Node 20
（browser MCP 用）、配置 Chromium 与 nuclei 模板，然后询问访问方式：

```
1) 仅内网 / 本机    （局域网可直接访问，无伪装闸门）
2) 开放外网         （默认开启反测绘闸门：必须用入口路径+口令访问）
```

选择后自动安装为 **systemd 系统服务并立即启动**（开机自启、崩溃自动拉起），
脚本结尾直接打印访问地址。外网模式下访问地址形如
`http://<IP>:8787/DARKIN-xxxxxxxx`，未带入口路径的请求一律返回假 nginx 页。

已有远程数据库可跳过脚本，直接手写 `config.json` 后运行 `./start.sh`。

### Windows

**一键安装（PowerShell，Win10/11 自带）**：

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/jianmo0x00/darkin-releases/main/install.ps1 | iex"
```

GitHub 访问不畅时改用 jsDelivr：

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://cdn.jsdelivr.net/gh/jianmo0x00/darkin-releases@main/install.ps1 | iex"
```

脚本自动完成：下载解压到 `%USERPROFILE%\DARKIN` → SHA256 校验 →
检测 PostgreSQL（未安装且系统有 winget 时可自动安装）→ 打印启动步骤。

**手动安装**：

1. 解压 zip 到任意目录（路径避免中文）
2. 安装 [PostgreSQL 16/18](https://www.postgresql.org/download/windows/)（或用远程库）
3. 复制 `config.example.json` 为 `config.json` 填连接信息
4. 双击 `启动DARKIN.bat`

包内已带 Python 3.13 与全部工具，无需额外安装。

### macOS

```bash
unzip darkin-0.8.1-macos-arm64.zip
cd darkin-0.8.1-macos-arm64
chmod +x start.sh darkin *.sh
brew install postgresql@16 && brew services start postgresql@16
createdb artex
./start.sh
```

首次运行如被 Gatekeeper 拦截：`xattr -dr com.apple.quarantine .` 后重试。

### 数据库配置（非 install-deps.sh 方式时）

复制 `config.example.json` 为 `config.json`，填 PostgreSQL 连接：

```json
{
  "database": {
    "host": "127.0.0.1",
    "port": 5432,
    "user": "artex",
    "password": "你的密码",
    "dbname": "artex",
    "sslmode": "disable"
  }
}
```

首次启动自动建表，无需手动迁移。

---

## 首次使用（三步）

1. **打开浏览器** → `http://127.0.0.1:8787`
   （局域网访问：面板里开「局域网访问」或 `./darkin -addr 0.0.0.0:8787`）
2. **设置管理员密码** → 用户名固定 `DARKIN`，密码自定（≥8 位）
3. **激活授权** → 粘贴购买得到的 voucher 码（`DARKIN-XXXXX-XXXXX-...`）

激活会自动绑定本机设备（一机一码），换取离线 license，之后无网也能用。

进入控制台后在「API KEY 配置」里填入 LLM Key（内置 Drink Ai / NodeDog /
DeepSeek / OpenRouter 等预设）。

---

## 激活说明

| 事项 | 说明 |
| --- | --- |
| 绑定方式 | voucher 首次使用时绑定本机设备 ID，不可跨机器复用 |
| 换机 / 重装系统 | 需要用新的 voucher，或联系作者解绑旧设备后重新激活 |
| 离线环境 | 可向作者申请与设备 ID 绑定的离线 license（`DARKIN1...`），直接粘贴 |
| 到期 | 授权页显示到期时间；到期后需续期 |
| 忘记密码 | 运行 `reset-password.sh`（Linux/macOS）/ `reset-password.*`（Windows） |

---

## 常见问题

**端口 8787 被占用？**
`./start.sh -addr 127.0.0.1:9000`（Windows：`start.bat -addr 127.0.0.1:9000`）。

**激活提示"在线激活未配置"？**
正常不会出现（官方服务器已内置默认）。若出现，检查 `config.json` 里
`activation_server` 是否被改成了无效地址，或设置环境变量
`ARTEX_ACTIVATION_SERVER=https://artex.darkin.ai`。

**激活失败 / 超时？**
确认能访问 `https://artex.darkin.ai`；公司内网/代理环境需要放行。
离线客户请改用离线 license。

**nuclei 提示找不到模板？**
包内已带 `nuclei-templates/`；如果误删，面板或文档里有重新下载方式。

**数据在哪？如何备份？**
所有业务数据在 PostgreSQL 里（默认库名 `artex`）；`data/` 目录是本地运行
状态与抓包索引。备份 = `pg_dump` + 打包 `data/`。

**会不会有后门 / 回传？**
除授权激活/吊销检查与你在 UI 里配置的 LLM 接口外，
程序不向任何第三方发送数据。

---

## 联系作者

购买授权、解绑换机、离线 license、二开合作：**@Jianmo**
