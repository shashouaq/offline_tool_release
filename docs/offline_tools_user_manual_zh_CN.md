# 离线工具平台 V1 使用说明书

## 1. 文档目标

本文档用于指导运维、测试和交付人员使用 `offline_tools_v1.sh` 完成离线工具包的下载、打包、传输和安装。

项目目录：

`D:\arm\offline_tool\offline_tool_release`

主脚本入口：

`offline_tools_v1.sh`

## 2. 产品定位

离线工具平台用于在联网环境中按目标 OS、版本和架构下载工具包组及其依赖，生成可在离线环境中安装的本地仓库压缩包。离线安装时必须使用包内仓库，不允许隐式联网安装。

核心规则：

1. 不同 OS、版本、架构的离线包必须分开。
2. 下载模式按用户选择的目标 OS/架构执行，不因本机已存在包而跳过。
3. 安装模式先识别本机环境，再筛选适用于本机的离线包。
4. 打包和安装界面只展示工具名称，不展开所有依赖包。
5. 所有菜单必须先完整展示，再等待输入。
6. 中文和英文菜单必须保持一致覆盖。

## 3. 目录说明

- `conf/`：系统源、工具清单、语言包、适配规则。
- `lib/`：下载、打包、安装、日志、菜单、元数据等模块。
- `utils/`：质量门禁、源检查、测试机同步、远程回归脚本。
- `docs/`：使用说明、决策记录、测试发现。
- `logs/`：运行日志、源检查日志、自动化验证日志。
- `output/`：离线包输出目录。

## 4. 环境准备

联网下载环境需要：

- 目标 OS 对应的包管理器，例如 `dnf/yum` 或 `apt-get`。
- `curl`、`tar` 等基础工具。
- 足够的临时空间。默认建议 `/tmp` 或工作目录不少于 20GB。

离线安装环境需要：

- 能解压离线包。
- 能使用本地仓库方式安装 RPM/DEB。
- 不依赖外部网络。

当 `/tmp` 空间不足时，脚本会尝试切换工作目录，root 环境下可尝试使用临时 tmpfs 工作区。非 root 环境会退回到 `/var/tmp/offline_tools_v1`。

## 5. 启动方式

在 Linux 或 WSL 中进入项目目录：

```bash
cd /mnt/d/arm/offline_tool/offline_tool_release
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

## 6. 下载模式

下载模式流程：

1. 选择语言。
2. 选择下载模式。
3. 选择目标 OS。
4. 选择目标架构。
5. 选择是否跳过 SSL 证书校验。
6. 执行环境自检。
7. 探测并筛选可用源。
8. 选择工具或包组。
9. 下载依赖闭包。
10. 构建本地仓库索引。
11. 生成离线包、manifest 和校验文件。

下载模式不判断本地是否已经存在同名离线包；用户选择什么目标环境和工具，脚本就按当前选择重新执行下载和打包。后续增量合并能力只在明确选择合并时使用。

## 7. 安装模式

安装模式流程：

1. 自动识别本机 OS、版本、架构和包类型。
2. 扫描 `output/` 或用户选择目录中的离线包。
3. 根据 `manifest.json` 判断兼容性。
4. 展示可安装工具列表。
5. 选择安装全部或选择性安装。
6. 安装前提示已安装、待安装和可升级状态。
7. 安装完成后提示继续安装其它工具包或返回主菜单。

如果离线包内 `packages/` 为空，必须视为失败，不能提示安装成功。

## 8. 离线包内容

离线包文件命名按目标环境区分，例如：

```text
offline_openEuler22.03_x86_64_merged.tar.xz
offline_Ubuntu22.04_aarch64_merged.tar.xz
```

离线包内应包含：

- `packages/`：RPM 或 DEB 文件。
- `repodata/` 或 DEB 本地索引。
- `manifest.json`：目标 OS、架构、工具列表、包数量等元数据。
- `.sha256`：校验文件。

界面展示离线包内容时，只展示支持安装的工具名称，不展示每个依赖包。

## 9. 源检查

正式发布前必须执行源检查：

```bash
./utils/check_sources.sh
```

检查规则：

- RPM 源检查 `repodata/repomd.xml`。
- DEB 源检查 `dists/<release>/InRelease` 或 `Release`。
- 检查结果写入 `logs/source_check_*.tsv`。
- 任意活动源失败时，脚本以非零状态退出。

质量门禁中可启用源检查：

```bash
OFFLINE_TOOLS_CHECK_SOURCES=1 ./utils/quality_gate.sh
```

## 10. 质量门禁

本地发布前执行：

```bash
./utils/quality_gate.sh
```

检查内容：

- 所有 shell 文件 `bash -n`。
- `.sh` 文件禁止 CRLF。
- 可用时执行 `shellcheck`。
- 可用时执行 `shfmt -d`。
- 主脚本版本 smoke test。

## 11. 同步测试机

默认测试拓扑：

- `172.18.10.61`：RPM 联网环境。
- `172.18.10.62`：DEB 联网环境。
- `172.18.10.64`：RPM 离线环境。
- `172.18.10.65`：DEB 离线环境。

同步命令：

```bash
./utils/sync_to_test_hosts.sh /mnt/c/Users/wei.qiao/Hkzy@8000 /root/offline_tool_release_v1
```

自动回归：

```bash
./utils/run_autonomous_validation.sh
```

测试日志保存在项目的 `logs/` 目录和远端项目目录下的 `logs/` 目录。

## 12. Windows 使用说明

Windows 环境建议通过 WSL 执行 Bash 脚本。正式 Windows 分发包应至少包含：

- 主脚本和全部 `conf/`、`lib/`、`utils/` 文件。
- 使用说明书 PDF。
- Windows 入口说明。

Windows 打包脚本：

```powershell
.\utils\package_windows_release.ps1 -Version v1
```

## 13. 常见问题

### 菜单没有显示，只出现选择提示

这是发布阻塞问题。需要检查 `logs/` 中是否有 `dep_check/menu_render` 或菜单渲染相关日志，并运行：

```bash
./utils/run_menu_regression.sh
```

### 某个工具下载失败但仍然打包成功

这是发布阻塞问题。失败工具不能计入最终支持安装工具列表，也不能让整包展示为全部成功。

### 包组名在真实环境中可安装，但脚本提示不支持

先确认目标 OS、架构和源是否选择正确，再检查：

- `conf/tools.conf`
- `conf/tool_os_rules.conf`
- `logs/source_check_*.tsv`
- 下载日志中的失败分类码

### 安装时提示 packages 目录为空

离线包无有效产物，安装必须失败。需要回看下载阶段日志、manifest 和本地仓库索引生成日志。

## 14. 发布前检查清单

1. `offline_tools_v1.sh --version` 输出 V1。
2. `utils/check_sources.sh` 返回 `failed=0`。
3. `utils/quality_gate.sh` 通过。
4. 菜单回归通过。
5. 中文和英文菜单均无乱码。
6. 远端四台测试机同步成功。
7. 远端联网/离线回归日志无发布阻塞错误。
