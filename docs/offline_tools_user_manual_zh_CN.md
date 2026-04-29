# 离线工具平台 V1.0 使用说明书

## 1. 这个工具解决什么问题

离线工具平台用于在有网络的 Linux 环境中下载指定 OS、架构和工具包组的完整依赖，并打包成可以带到离线环境安装的本地仓库包。

一句话流程：

```text
联网机器下载工具和依赖 -> 生成离线包 -> 拷贝到离线机器 -> 离线安装
```

适用场景：

- 生产环境不能访问外网，但需要安装排障、编译、监控、网络、桌面等工具。
- 不同 OS、不同架构需要分别准备离线包。
- 希望安装时只使用离线包内的本地仓库，不隐式联网。

主脚本：

```bash
./offline_tools_v1.sh
```

## 2. 目录说明

```text
offline_tool_release/
  offline_tools_v1.sh          主入口脚本
  conf/                        OS 源、工具列表、语言包、规则配置
  lib/                         下载、打包、安装、菜单、日志等核心模块
  utils/                       质量检查、源检查、远程回归、Windows 打包脚本
  docs/                        使用说明、设计记录、测试记录
  logs/                        运行日志
  output/                      离线包和校验文件输出目录
```

重要配置：

- `conf/tools.conf`：工具清单和 RPM/DEB 包组映射。
- `conf/os_sources.conf`：各 OS 版本的软件源。
- `conf/tool_os_rules.conf`：不同 OS/架构下的工具兼容规则。
- `conf/timeout.conf`：源探测、下载重试、临时空间等运行参数。

## 3. 使用前准备

联网下载机器需要：

- Linux 系统，推荐使用目标 OS 同族环境。
- RPM 系统需要 `dnf` 或 `yum`。
- DEB 系统需要 `apt-get`。
- 基础工具：`bash`、`curl`、`tar`。
- 建议 `/tmp` 或工作目录至少 20GB 可用空间。

离线安装机器需要：

- 能执行 Bash 脚本。
- 能解压 `.tar.xz`。
- RPM 环境能使用 `dnf/yum/rpm`。
- DEB 环境能使用 `apt-get/dpkg`。

脚本会自动检查 `/tmp` 空间。如果空间不足，root 环境会尝试临时扩容或切换 tmpfs 工作区，非 root 环境会切换到 `/var/tmp/offline_tools_v1`。

## 4. 启动工具

在项目目录中执行：

```bash
cd /root/offline_tool_release_v1
chmod +x offline_tools_v1.sh
./offline_tools_v1.sh
```

查看版本：

```bash
./offline_tools_v1.sh --version
```

查看帮助：

```bash
./offline_tools_v1.sh --help
```

## 5. 下载模式怎么用

下载模式用于在联网环境中生成离线包。

操作步骤：

1. 进入主菜单，选择 `下载模式`。
2. 选择目标 OS。RPM 系统只展示 RPM 目标，DEB 系统只展示 DEB 目标。
3. 选择目标架构，例如 `x86_64` 或 `aarch64`。
4. 选择是否跳过 SSL 证书校验。公网环境通常选“否”。
5. 等待环境自检完成。菜单会完整展示后再等待输入。
6. 选择工具分类或包组。
7. 确认下载。
8. 工具会探测可用源，跳过不可达源。
9. 工具会下载所选包组及完整依赖。
10. 下载完成后生成离线包、校验文件和快速索引文件。

输出示例：

```text
output/offline_openEuler22.03_x86_64_merged.tar.xz
output/offline_openEuler22.03_x86_64_merged.tar.xz.sha256
output/offline_openEuler22.03_x86_64_merged.tar.xz.header
```

注意：

- 不同 OS 和架构必须生成不同离线包。
- 工具下载失败时，不会被写入最终“支持安装工具”列表。
- 如果匹配的离线包中已经包含本次选择的工具，界面会提示已存在并跳过重复下载。
- 新版包会生成 `.header` 快速索引，安装模式读取离线包时会明显更快。

## 6. 安装模式怎么用

安装模式用于在离线环境中安装工具。

操作步骤：

1. 将离线包复制到项目的 `output/` 目录。
2. 在离线机器执行：

```bash
cd /root/offline_tool_release_v1
./offline_tools_v1.sh
```

3. 进入主菜单，选择 `安装模式`。
4. 工具会识别当前 OS、架构、包类型。
5. 工具会列出兼容的离线包。
6. 选择离线包。
7. 选择 `安装全部工具` 或 `选择性安装`。
8. 安装前会展示已安装、待安装、可升级数量。
9. 确认后开始安装。
10. 安装完成后可选择继续安装其他工具包或返回主菜单。

安装原则：

- 安装只使用离线包内的本地仓库。
- 不会隐式访问外部网络。
- 已安装工具会提示，可选择跳过或升级。
- 如果离线包中没有可安装软件包，安装会失败，不会误报成功。

## 7. 离线包里有什么

一个标准离线包包含：

- `manifest.json`：目标 OS、架构、包类型、工具列表、包数量等元数据。
- `packages_<OS>_<ARCH>/`：RPM 或 DEB 文件。
- `repodata/` 或 DEB 本地仓库索引。
- `.selected_tools`：工具级清单。
- `.tool_pkg_map`：工具到依赖包的映射，用于排障。
- `.sha256`：校验文件。
- `.header`：包外快速索引文件，用于快速展示离线包信息。

界面展示离线包内容时，只展示支持安装的工具名称，不展开所有依赖包。

## 8. 如何检查离线包是否完整

在离线包目录执行：

```bash
cd output
sha256sum -c offline_openEuler22.03_x86_64_merged.tar.xz.sha256
```

结果显示 `成功` 表示文件未损坏。

查看快速索引：

```bash
cat offline_openEuler22.03_x86_64_merged.tar.xz.header
```

可以看到：

```text
TARGET_OS="openEuler22.03"
TARGET_ARCH="x86_64"
PKG_TYPE="rpm"
TOOLS="kernel-dev,gcc-make"
PACKAGE_COUNT="227"
```

## 9. 源检查

发布前建议检查所有配置源：

```bash
bash utils/check_sources.sh
```

检查结果会写入：

```text
logs/source_check_YYYYMMDD_HHMMSS.tsv
```

质量门禁中启用源检查：

```bash
OFFLINE_TOOLS_CHECK_SOURCES=1 bash utils/quality_gate.sh
```

## 10. 质量检查

每次发布前执行：

```bash
bash utils/quality_gate.sh
```

检查内容：

- Bash 语法检查。
- `.sh` 文件禁止 CRLF。
- 主脚本版本 smoke test。
- 如果安装了 `shellcheck`，自动执行 shell 静态检查。
- 如果安装了 `shfmt`，自动执行格式检查。

## 11. Windows 环境怎么使用

Windows 上建议把项目包上传到 Linux 主机执行，不建议直接用 PowerShell 运行 Bash 主脚本。

生成 Windows 分发包：

```powershell
powershell -ExecutionPolicy Bypass -File .\utils\package_windows_release.ps1 -Version v1.0
```

生成后文件位于：

```text
output/offline_tool_v1.0_windows.zip
```

使用方式：

1. 在 Windows 解压 zip。
2. 将解压后的目录上传到联网 Linux 下载机。
3. 在 Linux 上执行 `bash offline_tools_v1.sh`。
4. 生成离线包后，再复制到离线 Linux 安装机。

## 12. 常见问题

### 菜单没有展示完整，只看到输入提示怎么办

这是交互界面问题。请保存 `logs/` 目录中的日志，并运行：

```bash
bash utils/run_menu_regression.sh
```

### 为什么选的工具没有下载

常见原因：

- 该工具已经存在于匹配 OS/架构的离线包中，已自动跳过。
- 当前 OS 仓库没有该包组。
- 当前架构不支持该包。
- 源不可达或依赖解析失败。

查看日志：

```bash
tail -n 200 logs/logs_$(date +%Y%m%d).log
```

### 为什么 htop 提示不可用

如果目标 OS 官方仓库没有 `htop`，工具会提示包名或包组不存在。需要换用同仓库存在的工具，或在 `conf/tool_os_rules.conf` 中配置适配规则。

### 安装时提示 packages 目录为空

说明离线包不完整或不是本工具生成的标准包。安装必须失败，不能继续。请重新下载和打包。

### 为什么安装时会升级本机已有包

如果离线包内依赖版本高于本机已安装版本，包管理器会按本地仓库事务进行升级。安装前界面会展示可升级数量。

## 13. 推荐发布检查清单

发布前按顺序检查：

1. `bash utils/quality_gate.sh` 通过。
2. `bash utils/check_sources.sh` 显示 `failed=0`。
3. 下载模式可以生成目标离线包。
4. `sha256sum -c` 校验通过。
5. 安装模式只展示兼容离线包。
6. 选择性安装能显示工具级清单。
7. 已安装工具能提示跳过或升级。
8. 中英文菜单均无乱码。
9. 10.61 最新目录已同步：`/root/offline_tool_release_v1`。
10. GitHub 已推送最新提交。

## 14. 现场人员最短操作流程

联网下载机：

```bash
cd /root/offline_tool_release_v1
./offline_tools_v1.sh
# 选择：下载模式 -> 目标 OS -> 架构 -> 工具 -> 确认下载
```

复制离线包：

```bash
scp output/offline_<OS>_<ARCH>_merged.tar.xz* root@离线机器:/root/offline_tool_release_v1/output/
```

离线安装机：

```bash
cd /root/offline_tool_release_v1
./offline_tools_v1.sh
# 选择：安装模式 -> 兼容离线包 -> 安装全部或选择性安装
```
