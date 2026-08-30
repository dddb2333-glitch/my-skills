# Skill Supply Chain v0.2

## 1. 目标

将网络来源、本地创作、适配版本、证据、治理决定、评测与 Runtime 部署拆成可追溯、可复现、不会互相冒充的记录层。

## 2. 数据流

```text
Discover
  ↓
Acquire
  ↓
sources/vendor/<namespace>/<skill>/<source-revision>/tree
  ↓
INTAKE + provenance/rights/security evidence
  ↓
Assess Decision
  ├─ REJECT
  ├─ KEEP_REFERENCE
  ├─ KEEP_FOR_EVAL
  └─ ADAPT_FOR_EVAL
        ↓
local/adapted authoring or upstream revision selection
        ↓
Revision Record
        ↓
Evaluation Evidence
        ↓
Admission Decision
        ↓
Pack Definition → Resolved Lock
        ↓
Deployment → Receipt
        ↓
Runtime-visible Skill copy
```

## 3. 身份模型

- `namespace`：Logical Skill 的 owner/命名空间，例如 `anthropic`、`vercel-labs`、`dddb2333-glitch`。
- `skill_id`：命名空间内的稳定 Skill ID。
- `origin.type`：`vendor | local | adapted`，不能拿来代替 namespace。
- `variant_id`：真正的行为变体，例如 `discovery-only`，不是 `adapted`。

## 4. Revision 模型

必须分开：

```text
revision_id       仓库内部 Revision 身份
version           人类版本，可为空
source_revision   上游 Git commit / release
content_digest    当前不可变内容摘要
```

Revision Record 不包含 `maturity.current`。Candidate / Validated / Stable 来自 Admission Decision，并由 Registry 派生有效状态。

## 5. Evidence 与 Decision

Evidence 回答“证据是什么”；Decision 回答“治理决定是什么”。二者物理目录和权限边界分开。

## 6. Vendor 安全边界

Raw vendor tree 可保留为普通文件，方便 Git diff 与 Inspect，但必须放在 `sources/vendor/`，且永不作为 Runtime Skill scan root。只有可疑/高风险内容才需要额外 archive/quarantine 封装。

## 7. 分类

Canonical 路径只依赖身份，不依赖 Domain。`classification.domains / roles / modalities / traits` 记录在 Logical Skill Record，由 `catalog/*.generated.json` 生成多维导航。

## 8. Evaluation 部署

INTAKE/CANDIDATE 可以在隔离 Pilot Runtime 中通过明确的 evaluation lock 部署。该部署不是 Admission，也不能被 Registry 解释为 Stable。

## 9. Public / Share Tools

当前只维持既有两个 GitHub 仓库，不新增第三个仓库。`myskills_private` 是私有 Canonical Repository；`my-skills` 保留现有公开/临时分享用途。最早的 `F:\SkillTemp\share-tools` 作为兼容工具原样保留，v0.2 Lite 不依赖它完成 Acquire / Evaluation Deployment，也不会自动修改它。若未来需要新的正式 Public Distribution，再单独设计，不在本版提前增加仓库。
