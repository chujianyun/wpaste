# WPaste 0.1.2 Release Checklist

2026-10-06：0.1.2 完整测试 60 项通过（参数化后 64 次），0 失败、0 跳过。通用版及两个分架构 Release archive 与 DMG 已验证，新版已安装启动。界面工具超时导致本次界面与权限实测待人工完成；Developer ID、公证、Intel 实机验收未完成。Xcode 另记录一条线程优先级运行时警告。详见 [0.1.2 发布说明](releases/v0.1.2.md)。

上一版记录（2026-09-06）：0.1.1 完整测试通过（54 项测试，含参数化用例共 57 次执行；0 失败、0 跳过）。通用版及 arm64 / x86_64 Release archive 已生成，三个 DMG 均校验通过；两个发布包挂载后确认内容与本次 archive 一致。本次通用 archive 已安装到 `/Applications/WPaste.app`，停止旧进程后在 Apple 芯片 Mac 上重新启动并持续运行。Intel 实机运行、Developer ID 分发签名、公证及下列手工验收仍待完成。详见 [0.1.1 发布说明](releases/v0.1.1.md)。

## Automated checks

- [x] Regenerate `WPaste.xcodeproj` from `project.yml`.
- [x] Run the complete macOS unit and integration test suite.
- [x] Archive a Release build with the macOS 15 deployment target.
- [x] Create and checksum-verify `build/WPaste.dmg`; inspect the archived app bundle metadata and binary architectures.
- [ ] Verify Developer ID signature when signing credentials are configured.
- [ ] Submit and staple notarization when Apple credentials are configured.

## Manual acceptance matrix

- [ ] Copy and paste text, URL, image, one file, and multiple files in Safari, Chrome, Finder, WeChat, WPS/Office, and Xcode.
- [ ] Verify deduplication and newest-first ordering.
- [ ] Verify search by text, URL, filename, and source application.
- [ ] Verify one item can belong to multiple Pinboards and deleting a Pinboard retains history.
- [ ] Verify single- and multi-display placement, full-screen apps, Spaces, light/dark appearance, and scaled displays.
- [ ] Verify missing accessibility permission degrades to copy-only.
- [ ] Verify missing source files remain visible and cannot be pasted.
- [ ] Verify pause, ignored applications, confidential/transient clipboard types, and quit cleanup.
- [ ] Verify screen-sharing redaction and link-preview opt-out.
