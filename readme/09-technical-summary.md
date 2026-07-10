# 技术摘要

LaunchPulse 使用 Rails 8、PostgreSQL、Hotwire、Solid Queue 和 Solid Cable，实现后台控制台、公开站点、Events API、异步聚合和实时更新。

## 主要模块

```text
页面区块 -> 页面分析 -> 内容补丁 -> A/B 实验
-> 访客事件 -> 转化归因 -> 实时看板
-> 采用实验版本 -> 发布记录 -> 内容差异与恢复
```

## 数据约束

- `Site.slug` 全局唯一，避免公开地址解析到错误账号。
- `Section.uid` 贯穿发布、实验、事件和历史恢复。
- 公开站点只读取 `PublishedSnapshot`。
- 实验原始版本和优化版本保存完整区块内容。
- `Assignment` 的实验、版本、访客和站点必须一致。
- `Conversion` 只能引用同一站点和访客的事件分配。
- 带幂等键的事件必须同时保存请求指纹。

## 事件处理

Events API 使用签名站点令牌认证。事件写入前会校验枚举、元数据、区块可见性和显式实验版本。

带幂等键的请求在 PostgreSQL advisory lock 中处理：

- 同键同内容返回已有事件；
- 同键不同内容返回错误；
- 冲突检查早于实验分配，失败请求不会留下副作用。

公开表单和订单将业务记录与事件放在同一事务中，避免出现业务记录成功但转化事件缺失的情况。

## 转化归因

归因顺序：

1. 显式实验与版本；
2. 页面区块；
3. 通用转化。

聚合服务只消费已经存在的实验分配，不会根据转化事件反向创建曝光记录。

## 实验管理

`Experiments::LifecycleService` 管理创建、暂停、继续、结束和结果应用。区块锁和行锁用于防止重复实验、重复结束和重复应用结果。

访客分流由 `Experiments::AssignmentService` 根据实验、访客和版本权重稳定计算。

## 发布管理

`Sites::SnapshotService` 在站点锁内生成连续版本号。版本内容使用规范化 JSON 计算校验和。

恢复历史内容前会检查：

- 校验和是否有效；
- 是否存在未处理完的实验；
- 区块是否可以按稳定 `uid` 恢复。

历史内容会发布为新版本，不会覆盖已有版本记录。

## 后台任务与实时更新

Solid Queue 负责事件聚合、访客模拟和延迟看板刷新。Solid Cable 将聚合后的事件、指标和实验结果推送到后台页面。

聚合服务与广播服务分开，实时更新策略不会改变统计口径。

## 关键代码

- `app/services/events/ingestion_service.rb`
- `app/services/events/payload_fingerprint.rb`
- `app/services/events/metadata_sanitizer.rb`
- `app/services/analytics/aggregation_service.rb`
- `app/services/experiments/lifecycle_service.rb`
- `app/services/experiments/assignment_service.rb`
- `app/services/sites/snapshot_service.rb`
- `app/services/sites/published_runtime.rb`
- `app/controllers/public/form_submissions_controller.rb`
- `app/controllers/public/checkouts_controller.rb`

## 检查

```bash
bin/check-demo
```

该命令运行 RSpec、Zeitwerk 检查、Tailwind 构建和交付包校验。完整代码风格与安全检查使用 `bin/ci`。

## 当前简化边界

这些地方是有意简化，不是遗漏：

- 智能审计是确定性输出，不调用外部模型接口。
- 结账只创建演示订单，没有接真实支付。
- 实验统计是透明近似，不是完整统计平台。
- 权限系统只保留演示所需能力。
- 事件采集是单条写入，已有 Rack::Attack 应用层基础限流；生产通过 SolidCache::Store 保存计数，连接同一 cache DB 的多个实例已共享限流状态。生产化还需批量上报、采样、网关/边缘限流、共享存储高可用与容量治理、租户级配额和监控。

## 如果进入生产，优先演进什么

1. 接入真实页面导入和编辑能力。
2. 接入外部模型，但保留稳定兜底输出和结构化校验。
3. 增加实验曝光事件、流量分配、人群定向和更严谨统计。
4. 加强账号权限、团队协作、接口密钥轮换和审计日志。
5. 把事件采集升级为批量写入、队列削峰和监控告警。
6. 增加发布审批、预览链接、任意版本对比和单区块恢复。
