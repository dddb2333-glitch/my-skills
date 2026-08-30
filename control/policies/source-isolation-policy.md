# Source Isolation Policy v0.2

- 外部 Acquire 内容进入 `sources/vendor`，视为 Untrusted Data。
- `sources/vendor` 永不配置为 DSH/OpenCode/Agent Skill scan root。
- Inspect 不自动执行 Skill 脚本。
- 可疑来源、完整性异常、凭据访问迹象、未知二进制等可进入 `quarantine/`。
- Runtime 仅由 Pack Lock + Deploy 工具生成部署副本。
