# Eval Policy v0.2

- E0：Static only
- E1：Normal + Boundary + Negative
- E2：+ No-Skill Baseline + Repeat
- E3：+ Cross-runtime + Composition + Regression

测试结果至少区分：`PASS / FAIL / INVALID / INFRA_FAILURE`。

`FAIL`：Skill 实际执行但行为不达标。
`INVALID`：测试前提不成立，例如 Skill 未正确挂载。
`INFRA_FAILURE`：Runtime/API/网络失败。

Test Verdict ≠ Governance Decision。
