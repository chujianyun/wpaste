# 「收藏到 Pinboard」右键菜单看似无反应

- 日期：2026-09-19
- 处理状态：代码与自动验证通过，已安装并启动；右键菜单与提示的实际交互等待已安装版本的人工验收。
- Git 状态：待提交、推送。

## 问题与根因

在剪贴板历史卡片上右键选择「收藏到 Pinboard」看似没有任何反应。功能本身存在（`HistoryOverlayView` 右键子菜单 → `PinboardStore.add` → SwiftData 持久化，`FeatureStoreTests` 已有覆盖并通过），但有两个体验问题导致「没反应」：

1. 尚未创建任何 Pinboard 时，「收藏到 Pinboard」子菜单为空，点开后什么都没有，看起来是死菜单。
2. 收藏动作执行后界面无任何反馈（菜单关闭后毫无变化），且失败被 `try?` 静默吞掉，用户无法判断成功还是失败。

## 修复

变更文件：`WPaste/Features/History/HistoryOverlayView.swift`

- 仅在已存在 Pinboard 时才显示「收藏到 Pinboard」菜单；没有 Pinboard 时菜单不出现（可通过历史面板顶部「+」先创建）。
- 收藏成功后显示即时提示「已收藏到「名称」」，失败时提示「收藏失败，请重试」，错误不再被静默吞掉。
- 提示为卡片面板底部的短暂浮层（`overlay-toast`），约 1.6 秒后自动消失。

## 自动验证与交付

| 检查 | 结果与证据 |
| --- | --- |
| 测试 | `Scripts/package-dmg.sh` 内 `xcodebuild test`（arm64）：58 通过 / 0 失败 / 0 跳过；xcresult：`DerivedData/.../Test-WPaste-2026.09.19_22-29-26-+0800.xcresult` |
| 构建与校验 | Archive：`build/WPaste.xcarchive/Products/Applications/WPaste.app`；DMG：`build/WPaste.dmg`；`hdiutil verify`：VALID |
| 签名与授权保留 | Apple Development: 605283073@qq.com (C7M68TN47R)，Team 7PXD675DGC；新产物 `codesign --verify --deep --strict --all-architectures` 通过；新产物满足旧版 DR（explicit requirement satisfied），身份兼容，授权可继承 |
| 旧进程退出 | 旧 PID 884（`/Applications/WPaste.app/Contents/MacOS/WPaste`），正常退出，无残留 |
| 安装 | `ditto` 完整替换 `/Applications/WPaste.app`，安装后签名复查通过 |
| 启动与功能 | `open -n /Applications/WPaste.app`，新进程 PID 25052 持续运行，无立即崩溃 |
| 界面修改验收 | 待人工验收：打开历史面板，确认无 Pinboard 时右键菜单不含「收藏到 Pinboard」；创建 Pinboard 后收藏卡片，确认底部出现「已收藏到」提示，且切换到该 Pinboard 能看到卡片 |
| 条件联动 | 不涉及：未改持久化结构、快捷键、CLI 或工程配置 |
| Git | 待提交推送 |

说明：本次构建的工作区还包含上一个任务（访达图片预览，见 `_reports/bug-fixes/20260909-finder-image-preview`）尚未提交的改动，会进入本次安装产物，但不纳入本次提交。
