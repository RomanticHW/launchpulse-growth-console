# 系统架构

LaunchPulse 使用 Rails 单体架构。后台控制台、公开站点、Events API、后台任务和实时更新位于同一应用中，共用业务模型和数据约束。

## 运行组成

### 后台控制台

后台用于管理站点、查看数据、分析页面、处理优化建议、创建实验和发布版本。

主要入口：

- `DashboardController`
- `SitesController`
- `AiAuditsController`
- `SectionPatchesController`
- `ExperimentsController`
- `PublishingController`

### 公开站点

公开站点路径为 `/s/:slug`。页面从最新发布版本读取区块内容，并根据访客的实验分配渲染对应版本。

表单和订单使用受控接口处理。页面浏览和按钮点击等轻量事件通过公开事件接口记录。

### Events API

`POST /api/v1/events` 接收外部事件，负责：

- 站点令牌认证；
- 参数和枚举校验；
- 元数据清洗；
- 区块可见性检查；
- 实验版本校验；
- 幂等处理；
- 事件写入和聚合任务入队。

### 后台任务

Solid Queue 执行事件聚合和访客模拟。事件完成聚合后，`Analytics::DashboardBroadcaster` 通过 Solid Cable 更新事件流、指标和实验面板。

## 代码职责

- 控制器：认证、参数处理和响应；
- 模型：关联、状态和基础数据约束；
- 服务对象：跨模型业务流程和事务；
- 后台任务：异步聚合与批量模拟；
- ERB 视图：后台和公开站点渲染；
- Stimulus 控制器：预览、抽屉、实时事件和轻量交互；
- RSpec：请求、服务、模型和系统流程验证。

## 关键服务

### `Sites::PublishedRuntime`

读取公开站点可见的页面区块，并处理实验版本覆盖。所有公开入口都使用相同的区块可见性判断。

### `Sites::SnapshotService`

负责发布、版本差异和历史恢复。版本内容使用规范化 JSON 计算校验和。

### `Experiments::LifecycleService`

管理实验创建、暂停、继续、结束和结果应用，并防止同一区块出现多个未处理完的实验。

### `Events::IngestionService`

处理外部事件认证、幂等、区块校验和显式实验归因。带幂等键的并发请求使用 PostgreSQL advisory lock 保持处理顺序一致。

### `Analytics::AggregationService`

聚合事件并记录转化。归因优先级依次为显式实验、页面区块和通用转化。

## 数据库

项目使用 Rails 8 多数据库配置：

- 主业务库；
- 缓存库；
- Solid Queue 队列库；
- Solid Cable 实时通道库。

Web 与任务进程必须连接到同一套 Cable 数据库，后台任务完成后页面才能收到实时更新。
