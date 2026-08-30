# share-tools v0.2.1 Framework-Aware v2.3 Audited

工作区内的活动位置：`F:\SkillTemp\tools\share-tools`。公开快照中仍使用稳定目录名 `share-tools/`，因此这次工作区整理不会改变公开仓库结构。

运行时会从工具目录向上识别同时包含 `skill-packs` 和 `myskills-private` 的工作区根目录；本地 Preview 与临时远程克隆写入该根目录下的 `work\share-tools`，不再依赖独立的 `F:\SkillMirrorWork`/`F:\SkillMirrorPreview` 固定目录。

适配当前 `SkillTemp v0.2.1 Lite` 双仓库结构：

- PRIVATE Canonical：`dddb2333-glitch/myskills_private`
- PUBLIC Framework：`dddb2333-glitch/my-skills`

本版是在 v2.1 Remote-Aware 基础上逐文件审查后的收口版，重点不是继续增加架构，而是修复发布器、安装器、验证器之间的语义和执行差异。

## 当前公开边界

默认只公开：

```text
Skill_Supply_Chain_v0.2.md
control/policies/
control/schemas/
share-tools/
README.md
.gitattributes
.public-export-manifest.json
PUBLIC_EXPORT_SHA256.txt
```

默认不公开：`sources/`、`library/`、`records/`、`evidence/`、`decisions/`、`registry/`、`catalog/`、`packs/`、`deployment/`、`quarantine/`、`archive/`、`exports/`、`tools/`、`tests/`。

## v2.3 审查后修正

1. `.supply-chain-version.json` 仍是优先证据，但不再是唯一身份凭据；缺失时使用一组具体的 v0.2.1 Framework 锚点判定“结构兼容”，且明确标记 `compatible-not-version-proven`，不伪称精确版本已被证明。
2. 不再递归扫描整个 PRIVATE 仓库的 reparse point；只对实际 allowlist 路径进行逐项安全复制，避免无关 vendor/source 树导致误阻塞或递归风险。
3. Required 复制数量必须与 Required 规则数量完全一致；重复/重叠 allowlist、路径穿越、Windows 保留路径均会阻断。
4. 增加 PUBLIC 文件数量、单文件大小、总大小和扩展名 Gate；Secret 扫描不再用“大文件直接跳过”的降级路径。
5. 增加常见 OpenAI/OpenRouter/DeepSeek/OpenCode/Google/GitHub/Pixiv 凭据模式扫描。
6. 使用 `.gitattributes: * -text` + fresh repo `core.autocrlf=false`，避免 Git 自动换行转换破坏导出 SHA256 的字节意义。
7. 所有生成文本统一通过 .NET 写 UTF-8 no BOM，兼容 Windows PowerShell 5.1 与 PowerShell 7，避免同一导出在不同 PowerShell 版本出现 BOM 差异。
8. `--force-with-lease` 保留，并增加 push 后远程 HEAD 二次验证；“执行 push”不再自动等于“发布完成”。
9. PRIVATE/PUBLIC URL 相同会硬阻断，避免配置错误把 fresh snapshot 推到 Canonical 仓库。
10. Git 身份检查改为 fresh repo 真正会继承的 global/system identity，不再可能被调用目录的 local config 假通过。
11. 本地 Preview 的 manifest 现在记录 `source_mode` 与 `source_worktree_dirty`，不会再用一个 commit SHA 假装完全绑定未提交的工作树内容。
12. `ensure-private-source.ps1` 改为使用 `config.ps1` 的 repo slug；修改可见性要求显式 `-Apply`，并再次确认和执行后校验。
13. 安装器增加 SHA256 自校验、安装后复验、嵌套路径保护、源位于旧 target 内时的 staging，以及自定义 Target 对应的 archive 备份位置。
14. `README`、Public README、clear-public 文案修复了 v2.1 中“marker 必须存在”和“只保留两个项目但实际还有 hash manifest”等矛盾。
15. `Write-PublicExportManifest` 更新为 schema 2 / exporter v2.3，并记录 identity source/confidence、allowlist/denylist hash。
16. `self-test.ps1` 扩展为 12 组测试，其中包含本地 bare Git 的真实 `force-with-lease` 竞争写入测试，不访问 GitHub。
17. 所有 `.cmd/.bat` 启动器会优先固定 `F:\PowerShell\7\pwsh.exe`，找不到时再搜索 PATH 中的 `pwsh.exe`，最后回退 `powershell.exe`。

## 推荐顺序

安装后先运行：

```text
05_SELF_TEST.cmd
00_CHECK_PRIVATE_CANONICAL.cmd
01_PREVIEW_PUBLIC_FRAMEWORK.cmd
```

三者都通过并检查 Preview 内容后，再运行：

```text
02_PUBLISH_PRIVATE_TO_PUBLIC.cmd
```

正式发布要求输入 `PUBLISH`。脚本正式发布只从 PRIVATE remote 已提交的 `main` 构建，不会把 `F:\SkillTemp\myskills-private` 的未提交工作树直接推到 PUBLIC。

如果 `00_CHECK_PRIVATE_CANONICAL.cmd` 显示 PRIVATE remote 缺少 Framework，而本地 Canonical 是完整的，请按 `TROUBLESHOOT_PRIVATE_REMOTE.md` 先解决 PRIVATE/main 未同步问题，不要绕过 Required Gate。

## 其他入口

- `03_CLEAR_PUBLIC_KEEP_TOOLS.cmd`：清除 Public Framework payload，保留 README、完整 share-tools 和完整性清单；仍使用 lease + post-push verification。
- `04_ENSURE_PRIVATE_REPO.cmd`：只检查 PRIVATE 可见性，不修改；需要修改时手工运行 `ensure-private-source.ps1 -Apply`。
- `PUBLISH_FRAMEWORK.bat` / `publish-framework.ps1`：兼容旧入口，内部只转发到正式发布器，不维护第二套发布逻辑。
- `INSTALL_SHARE_TOOLS.cmd`：安装前后都会校验 `SHA256SUMS.txt`。

## 边界说明

Fresh-snapshot + force-with-lease 会重写当前 Public `main`。它不能删除此前已被 clone、fork、下载、缓存或服务端保留的历史副本，因此真正敏感凭据永远不应进入 Public Git 历史。

## v2.3 Windows PowerShell / non-Git local fix

- `-UseLocalCanonical` now validates a plain local canonical directory even when it has no `.git`; this is structural validation only and does **not** make the directory publishable provenance.
- Local preview also supports a non-Git canonical directory and records `source_commit: null` / unknown dirty state.
- Formal publish remains remote-authoritative: it still clones PRIVATE `main` and will never publish directly from an uncommitted local directory.
- Native Git/GitHub probe commands now run through an exit-code capture helper so Windows PowerShell 5.1 does not turn an expected non-zero probe into a premature `NativeCommandError` under `$ErrorActionPreference = 'Stop'`.

### Local-only helpers (no ExecutionPolicy setup needed)

- `00A_CHECK_LOCAL_CANONICAL.cmd` — validates `F:\SkillTemp\myskills-private` even if it is currently a plain non-Git directory.
- `01A_PREVIEW_LOCAL_FRAMEWORK.cmd` — builds a local Framework preview from that directory; if it is non-Git, provenance is explicitly recorded as unknown.

These helpers do not publish. Formal publication still clones PRIVATE `main`.
