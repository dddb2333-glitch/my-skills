# Audit Report — share-tools v2.3

审查范围：安装器、配置、allowlist/deny-list、Canonical 检查、Preview、正式发布、Public 清理、PRIVATE 可见性检查、兼容 wrapper、self-test、所有 CMD/BAT 启动器、文档与校验清单。

## 审查中实际发现并修正的问题

- v2.1 README 仍残留“marker 必须存在”的旧说法，与 Remote-Aware 实现冲突。
- v2.1 manifest exporter 仍标记 v2，未体现 v2.1 修复。
- v2.1 对整个 PRIVATE tree 做 recursive reparse scan，范围过宽，可能因无关 source/vendor 内容阻塞 Framework export。
- v2.1 secret scanner 对 >2 MiB 文件直接跳过，存在明确扫描旁路。
- v2.1 生成 UTF-8 使用 `Set-Content -Encoding UTF8`，在 Windows PowerShell 5.1 与 PowerShell 7 的 BOM 行为不一致。
- v2.1 formal push 后缺少 remote HEAD completion verification。
- v2.1 Git identity check 可能被调用目录的 local Git config 假通过，而 fresh repo 实际不能继承该 local identity。
- v2.1 local preview 允许 dirty working tree，但 provenance 只有 commit SHA，绑定语义不完整。
- v2.1 installer 在 source 位于 target 子目录时存在“先移动 target 导致 source 路径失效”的结构风险，且 custom Target 仍硬编码备份到 F:\SkillTemp\archive。
- v2.1 PublicToolFiles 未包含 README 所引用的 troubleshooting 文档；作为公开工具集不闭包。
- v2.1 clear-public 的“README + share-tools only”说法与实际生成 SHA manifest 不一致。
- v2.1 double-quoted here-string 中 Markdown backtick 存在被 PowerShell 当转义符处理的风险。
- v2.1 self-test 覆盖不足，未覆盖 structural fallback、invalid metadata、rule traversal/overlap、size/extension gate、lease race、post-push semantics。

以上均已在 v2.3 收口。

## 构建环境验证

- ZIP CRC：构建后执行。
- 包内 SHA256：构建后逐文件复核。
- 文本静态检查：执行旧路径/普通 `--force`/stale version strings/危险 allowlist 关键词/文件闭包检查。
- Git lease 语义：通过 Linux Git 对等命令额外验证 `--force-with-lease=<ref>:<old>` 在 competing update 后会拒绝 stale push。
- Windows PowerShell live execution：当前构建容器没有 `powershell.exe`/`pwsh.exe`，因此不能诚实标记为已在 Windows 运行。包内 `05_SELF_TEST.cmd` 提供 14 组本地实测，其中 Git 测试只使用临时 bare repo，不访问网络。

因此本包的结论是：已完成逐文件逻辑审查、修复和构建级验证；没有已知的静态/结构性错误。最终 Windows 运行时兼容性由 `05_SELF_TEST.cmd` 在目标机直接验收。

## v2.3 regression repair

The v2.2 audit missed a Windows PowerShell 5.1 interaction: `git rev-parse` used as a probe can emit a native error record for a non-repository while `$ErrorActionPreference='Stop'`, terminating before the function can inspect `$LASTEXITCODE`. v2.3 routes probe-style native calls through `Invoke-NativeCapture` and adds a non-Git regression case.

The audit also corrected an architectural mismatch: local canonical structural checking/preview does not require Git provenance, while formal publishing still requires the PRIVATE remote commit. A non-Git local tree is therefore accepted only for local validation/preview with explicit unknown provenance.

## v2.3.1 workspace-layout addendum

The active local package moved to `F:\SkillTemp\tools\share-tools`; the public snapshot directory remains `share-tools/`, so public repository compatibility is unchanged. Local Canonical, work, and preview paths are now derived from a workspace root containing both `skill-packs` and `myskills-private`, with the existing `F:\SkillTemp` layout retained as a compatibility fallback. The installer default target was updated accordingly.

Target Windows PowerShell 5.1 validation also exposed that `[AllowNull()][string]` still binds `$null` as an empty string and can fail a mandatory parameter. Nullable non-Git provenance parameters now explicitly allow both null and empty-string binding before rendering the documented `(none)` value.
