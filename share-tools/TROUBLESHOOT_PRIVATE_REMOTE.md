# PRIVATE remote compatibility troubleshooting

当 clone 日志只有极少对象（例如 `Enumerating objects: 3`）时，常见情况是 PRIVATE/main 仍只有一个 README 类极简提交。发布器无法从不存在的远程 Canonical 内容中导出 Framework。

## v2.3 的身份规则

- 如果 `.supply-chain-version.json` 存在：严格校验 `layout`、`schema_version`、`canonical_role`；显式元数据不匹配会直接 BLOCK。
- 如果 marker 不存在：要求一组具体 Framework 锚点存在，结果只标记为“结构兼容”，不会伪称精确历史版本已证明。

## 检查本地和远程

```powershell
cd F:\SkillTemp\tools\share-tools
.\check-private-canonical.ps1 -UseLocalCanonical
.\check-private-canonical.ps1
```

如果 LOCAL PASS 而 REMOTE FAIL，说明 `F:\SkillTemp\myskills-private` 的新 Canonical 尚未正确 commit/push 到 `myskills_private/main`。

不要通过删除 Required Gate 来绕过这个问题，否则会重新引入旧版“核心文件没复制但最后显示 DONE”的 False Success。
