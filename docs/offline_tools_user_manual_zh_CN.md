# 离线工具平台 V1.0 用户使用说明书

## 1. 工具用途

离线工具平台用于把 Linux 工具包和完整依赖提前下载好，做成可复制到离线服务器安装的本地仓库包。

最短理解：

```text
联网服务器下载 -> 生成离线包 -> 拷贝到离线服务器 -> 从离线包安装
```

适合这些场景：

- 生产服务器不能访问外网。
- 需要安装排障、网络、监控、编译、桌面等工具。
- 需要按不同 OS、版本、架构分别准备离线包。
- 安装时必须只使用离线包内的本地仓库。

## 2. 新环境拿到项目后先看哪里

项目下载或解压后，保留这些文件和目录即可运行：

```text
offline_tool_release/
  offline_tools_v1.sh
  README.md
  conf/
  lib/
  utils/
  docs/
```

运行过程中会自动创建：

```text
logs/
output/
```

说明：

- `logs/` 保存运行日志，不需要随发布包保留。
- `output/` 保存生成的离线包，不需要随发布包保留。
- 离线包、校验文件、`.header` 快速索引都是运行后生成的产物。

## 3. 推荐部署方式

### 3.1 在联网服务器准备下载环境

把项目上传到联网 Linux 服务器，例如：

```bash
cd /root
unzip offline_tool_v1.0.2_windows.zip -d offline_tool_release_v1
cd /root/offline_tool_release_v1
```

如果是从 GitHub 下载源码包：

```bash
cd /root/offline_tool_release
chmod +x offline_tools_v1.sh
```

### 3.2 在离线服务器准备安装环境

离线服务器也需要放一份同样的项目目录，然后把联网服务器生成的离线包复制到离线服务器的 `output/` 目录。

```text
offline_tool_release/
  offline_tools_v1.sh
  conf/
  lib/
  utils/
  docs/
  output/
    offline_<OS>_<ARCH>_merged.tar.xz
    offline_<OS>_<ARCH>_merged.tar.xz.sha256
    offline_<OS>_<ARCH>_merged.tar.xz.header
```

## 4. 启动工具

进入项目目录：

```bash
cd /root/offline_tool_release_v1
```

启动：

```bash
bash offline_tools_v1.sh
```

查看版本：

```bash
bash offline_tools_v1.sh --version
```

查看帮助：

```bash
bash offline_tools_v1.sh --help
```

## 5. 下载模式

下载模式在联网服务器上执行，用来生成离线包。

操作步骤：

1. 启动脚本。
2. 选择语言。
3. 主菜单选择 `下载模式`。
4. 选择目标 OS。
5. 选择目标架构，例如 `x86_64` 或 `aarch64`。
6. 选择是否跳过 SSL 证书校验。公网源通常选择“不跳过”。
7. 等待环境自检完成。
8. 选择工具分类或工具包组。
9. 确认下载。
10. 等待下载、依赖解析、仓库索引生成和打包完成。

下载完成后，文件会出现在：

```text
output/
```

典型产物：

```text
offline_openEuler22.03_x86_64_merged.tar.xz
offline_openEuler22.03_x86_64_merged.tar.xz.sha256
offline_openEuler22.03_x86_64_merged.tar.xz.header
```

每个文件的作用：

- `.tar.xz`：真正的离线包。
- `.sha256`：校验离线包是否损坏。
- `.header`：快速索引，用于快速显示离线包支持哪些工具。

注意事项：

- 不同 OS、版本、架构要分别打包。
- 选择的工具如果已经存在于同 OS、同架构的离线包中，会提示已存在并跳过重复下载。
- 某个工具下载失败时，不会被标记为已打包成功。
- 打包界面只展示工具名，不展示所有依赖包。

## 6. 安装模式

安装模式在离线服务器上执行，用来从离线包安装工具。

操作步骤：

1. 把离线包复制到项目的 `output/` 目录。
2. 启动脚本。
3. 主菜单选择 `安装模式`。
4. 工具自动识别当前 OS、架构和包类型。
5. 工具列出兼容离线包。
6. 选择要安装的离线包。
7. 选择 `安装全部工具` 或 `选择性安装`。
8. 确认安装。
9. 安装完成后选择继续安装其他工具包或返回主菜单。

安装规则：

- 只使用离线包内的本地仓库。
- 不隐式访问外部网络。
- 会提示已安装、待安装、可升级包数量。
- 离线包为空或缺少软件包时，安装会失败，不会误报成功。

## 7. 如何复制离线包

从联网服务器复制到离线服务器时，建议复制同名前缀的三个文件：

```bash
scp output/offline_openEuler22.03_x86_64_merged.tar.xz* root@<离线服务器IP>:/root/offline_tool_release_v1/output/
```

复制后在离线服务器校验：

```bash
cd /root/offline_tool_release_v1/output
sha256sum -c offline_openEuler22.03_x86_64_merged.tar.xz.sha256
```

显示 `成功` 表示离线包未损坏。

## 8. 如何确认离线包内容

查看快速索引：

```bash
cat output/offline_openEuler22.03_x86_64_merged.tar.xz.header
```

示例：

```text
TARGET_OS="openEuler22.03"
TARGET_ARCH="x86_64"
PKG_TYPE="rpm"
TOOLS="kernel-dev,gcc-make"
PACKAGE_COUNT="227"
```

安装菜单中也会展示支持安装的工具列表。

## 9. 源检查

如果下载失败，先检查软件源：

```bash
bash utils/check_sources.sh
```

检查结果保存在：

```text
logs/source_check_YYYYMMDD_HHMMSS.tsv
```

如果源不可达：

- 换一个网络环境。
- 检查代理、防火墙、DNS。
- 修改 `conf/os_sources.conf` 中对应 OS 的源地址。

## 10. 质量检查

发布或修改脚本后，建议执行：

```bash
bash utils/quality_gate.sh
```

它会检查：

- Bash 语法。
- `.sh` 文件是否存在 Windows CRLF 换行。
- 主脚本版本是否可正常输出。
- 如果系统安装了 `shellcheck` 或 `shfmt`，会自动执行更严格检查。

## 11. Windows 用户怎么用

Windows 分发包用于下载、保存和转移项目，不建议直接在 PowerShell 中运行 Bash 主脚本。

推荐方式：

1. 在 Windows 解压发布包。
2. 上传整个目录到联网 Linux 服务器。
3. 在 Linux 服务器执行：

```bash
bash offline_tools_v1.sh
```

如果需要重新制作 Windows 分发包，在项目根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\utils\package_windows_release.ps1 -Version v1.0.2
```

## 12. 常见问题

### 12.1 选工具后提示已经存在

说明同 OS、同架构的离线包中已经包含该工具。工具会跳过重复下载，避免重复打包。

### 12.2 安装模式找不到兼容离线包

检查：

- 离线包是否放在 `output/` 目录。
- 离线包的 OS 是否匹配当前系统。
- 离线包的架构是否匹配当前机器。
- 离线包是否有 `.header` 或内置 `manifest.json`。

### 12.3 安装时报 packages 目录为空

说明离线包不是有效安装包，或打包过程失败。需要回到联网服务器重新下载并打包。

### 12.4 中文菜单乱码

确认终端使用 UTF-8，例如：

```bash
export LANG=zh_CN.UTF-8
```

如果仍乱码，可以选择 English 菜单。

### 12.5 /tmp 空间不足

脚本会尝试自动处理。如果仍失败，可以手动指定工作目录：

```bash
export OFFLINE_TOOLS_WORK_DIR=/var/tmp/offline_tools_v1
bash offline_tools_v1.sh
```

## 13. 一页流程图

```text
联网服务器
  |
  | 1. 下载模式
  v
生成 output/offline_<OS>_<ARCH>_merged.tar.xz
  |
  | 2. 复制 .tar.xz / .sha256 / .header
  v
离线服务器
  |
  | 3. 安装模式
  v
从本地仓库安装工具
```

## 14. 最短操作清单

联网服务器：

```bash
cd /root/offline_tool_release_v1
bash offline_tools_v1.sh
```

选择：

```text
下载模式 -> 目标 OS -> 架构 -> 工具 -> 确认下载
```

离线服务器：

```bash
cd /root/offline_tool_release_v1
bash offline_tools_v1.sh
```

选择：

```text
安装模式 -> 兼容离线包 -> 安装全部或选择性安装
```
