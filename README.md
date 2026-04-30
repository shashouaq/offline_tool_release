# offline_tool_release

离线工具平台用于在联网 Linux 服务器下载工具包和完整依赖，生成可复制到离线服务器安装的本地仓库包。

## 快速开始

```bash
cd offline_tool_release
bash offline_tools_v1.sh
```

典型流程：

```text
联网服务器：下载模式 -> 选择目标 OS/架构/工具 -> 生成离线包
离线服务器：安装模式 -> 选择兼容离线包 -> 安装全部或选择性安装
```

## 必要目录

全新环境只需要这些文件和目录：

- `offline_tools_v1.sh`
- `README.md`
- `conf/`
- `lib/`
- `utils/`
- `docs/`

运行时会自动创建：

- `logs/`
- `output/`

发布包不会包含日志、离线包、校验文件、快速索引或临时压缩包。

## 常用命令

```bash
bash offline_tools_v1.sh
bash offline_tools_v1.sh --version
bash utils/check_sources.sh
bash utils/quality_gate.sh
```

## 用户文档

- `docs/offline_tools_user_manual_zh_CN.md`
- `docs/offline_tools_user_manual_zh_CN.pdf`
- `docs/offline_tools_a4_quick_guide_zh_CN.pdf`

## Windows 分发包

```powershell
powershell -ExecutionPolicy Bypass -File .\utils\package_windows_release.ps1 -Version v1.0.2
```
