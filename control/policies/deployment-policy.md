# Deployment Policy v0.2

- Admission ≠ Deployment。
- Pack Definition ≠ Lock ≠ Receipt。
- Evaluation 环境允许通过专用 eval lock 部署 INTAKE/CANDIDATE，但 receipt 必须标记 `purpose=evaluation`。
- Runtime 目录不是 Canonical Library。
- 部署前后均验证 content digest，记录 receipt。
