# WPaste Repository Instructions

本文件适用于整个仓库及其所有子目录。

## 开发要求

- 所有新增功能、Bug 修复、行为变更、运行时配置变更以及资源变更，都必须完成实现、测试、打包、安装和启动验证后才能宣布完成。
- 每次新增功能或修复 Bug，测试通过且当前构建产物校验成功后，都必须先终止旧 WPaste 进程，再替换安装并重新启动；启动验证通过后必须提交并推送到远端，完成整个流程后才能宣布完成。
- 使用测试驱动开发：先添加会因缺少目标行为而失败的测试，确认失败原因正确，再添加最小实现并运行完整测试套件。
- 不得跳过失败测试、忽略编译警告，或用旧产物代替当前提交生成的产物。
- 修改 `project.yml` 后必须重新运行 XcodeGen，生成并提交同步后的 `WPaste.xcodeproj`。
- 仅修改 Markdown、注释或其他不会影响构建和运行结果的文档时，可以跳过打包、安装和启动步骤；仍需执行适合该改动的格式与 Git 差异检查。

## 自动验证、打包、安装和启动

完成任何影响应用运行结果的改动后，必须依次执行以下流程：

1. 在仓库根目录执行 `Scripts/package-dmg.sh`。该脚本必须先运行完整测试，再生成 Release archive 和 `build/WPaste.dmg`；任一步骤失败都立即停止。
2. 执行 `hdiutil verify build/WPaste.dmg`，确认 DMG 校验有效。
3. 确认待安装应用来自当前构建：`build/WPaste.xcarchive/Products/Applications/WPaste.app`。
4. 终止已运行的 WPaste 实例，并确认旧进程已退出后再替换应用；目标只能是 bundle identifier `com.chujianyun.wpaste` 或可执行文件名 `WPaste`，不得误杀其他进程。
5. 将新应用安装到固定路径 `/Applications/WPaste.app`。替换前必须确认目标路径精确等于 `/Applications/WPaste.app`；构建或校验失败时不得覆盖已有版本。
6. 执行 `open -n /Applications/WPaste.app` 启动新版本，并确认 `/Applications/WPaste.app/Contents/MacOS/WPaste` 进程保持运行，没有立即崩溃。
7. 启动验证完成后保持应用运行，方便用户立即验收。
8. 对于新增功能或 Bug 修复，按下方 Git Workflow 提交改动、合并到 `main`（如适用）并推送到远端，确认推送成功。

推荐的安装命令为：

```zsh
ditto "build/WPaste.xcarchive/Products/Applications/WPaste.app" "/Applications/WPaste.app"
open -n "/Applications/WPaste.app"
```

若 `/Applications` 写入失败、签名/公证凭据缺失、系统权限阻止启动或目标应用无法安全替换，必须保留已生成产物并明确报告阻塞原因；不得声称已安装或已启动。

## Git Workflow

- 每次新增功能或修复 Bug，在完整测试、打包、校验、停止旧进程、替换安装和重新启动验证均成功后，必须自动提交本次任务的相关改动；不得夹带无关的未提交改动。
- 如果改动是在新建分支上开发的，必须自动将该分支合并到 `main`，无需等待额外确认；如果合并失败或出现冲突，必须说明原因并继续处理。
- 完成提交及合并后，必须自动将 `main` 推送到配置的远端，无需等待额外确认；不得强制推送。只有确认推送成功后，才能将本次功能或 Bug 修复标记为完成。
- 如果远端未配置、认证失败或推送被拒绝，必须明确报告阻塞原因并保留本地提交，不得声称已推送或已完成。

## 完成报告

每次运行时改动的最终报告必须包含：

- 完整测试结果（通过数、失败数和跳过数）。
- Release archive 与 DMG 的实际路径。
- DMG 校验结果。
- 实际安装路径。
- 启动验证结果及运行中的进程信息。
- 对于新增功能或 Bug 修复，提交信息、合并结果（如适用）、推送的远端与分支及推送结果。
- 因凭据、权限或人工交互尚未完成的签名、公证或手工验收项。
