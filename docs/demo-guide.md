# 演示指南

下面是一条相对省时间的演示路线。可以先按 5 分钟路径看完整闭环，再用 10 分钟版本展开几个关键技术边界。

## 5 分钟路径

### 1. 打开站点详情

登录后台后，选择一个站点，推荐先看 `clearleaf-skincare`。

看什么：

- 左侧是结构化页面区块。
- 中间是站点预览。
- 右侧是建议和实验。
- 项目重点是网站发布后的增长闭环，不是拖拽建站器。

对应实现：

- Rails 8 单体承载后台、公开站点、事件接口、后台任务和实时刷新。
- 页面以 `Section` 为增长动作单位，建议、补丁、实验、归因和回滚都围绕区块展开。

### 2. 生成诊断

点击 `生成诊断`，查看建议卡片。

看什么：

- 建议关联具体区块。
- 建议包含问题、改动字段、预期影响和可执行补丁。
- 当前建议是确定性输出，便于本地演示和测试稳定。

对应实现：

- `Ai::GrowthAuditService` 生成结构化建议。
- `SectionPatch` 保存修改前后的 props，为后续实验提供稳定证据。

### 3. 预览并应用补丁

点击 `预览改动`，确认预览变化后返回站点详情页，点击 `应用到草稿`。

看什么：

- 预览不写数据库。
- 应用只修改后台草稿。
- 公开页面仍然读取已发布快照，不会立即看到草稿变化。

对应实现：

- `SectionPatch#apply!` 更新 `section.props`，并保留 `before_props` 和 `after_props`。
- `PublishedSnapshot` 隔离草稿和公开运行时。

### 4. 创建实验

点击 `测试原版和新版`。

看什么：

- 实验包含 `原版本` 和 `建议版本`。
- 两个版本都保存完整 props。
- 同一区块不能同时存在多个未结束实验。

对应实现：

- `Experiments::LifecycleService` 负责实验创建、暂停、完成和应用胜出版本。
- control variant 的 props 来自补丁应用前的数据，避免后续发布改变实验基线。

### 5. 在公开页触发转化

点击 `公开预览`，在公开页提交表单，或点击商品 `购买`、价格方案 `选择方案`。

看什么：

- 公开页会按访客做稳定分流。
- 表单和结账事件会带上区块标识。
- 商品和价格方案结账最终以 `order_created` 作为主转化。

对应实现：

- `Experiments::AssignmentService` 基于访客和实验做稳定哈希分流。
- 表单和结账走受控入口，强转化不能只靠公开埋点伪造。

### 6. 查看实时数据并发布

回到后台，看实时事件流、指标和实验数据。可以点击 `模拟 1000 位访客` 快速生成分析事件。随后点击实验的 `完成`，选择 `应用 原版本` 或 `应用 建议版本`，最后点击 `发布`，在发布快照区域点击 `对比`。

看什么：

- 事件入库后由后台任务聚合。
- 聚合结果通过实时通道刷新后台。
- 实验完成后需要明确应用胜出版本。
- 发布生成带 checksum 的快照，可以对比和回滚。

对应实现：

- Solid Queue 执行聚合和模拟任务。
- Solid Cable 做跨进程实时刷新。
- `Sites::SnapshotService` 负责发布、差异和回滚。

## 10 分钟路径

如果时间更充裕，可以按下面顺序看：

1. 后台打开一个站点，确认页面由结构化区块组成。
2. 点击 `公开预览`，确认公开页只读已发布版本。
3. 回后台点击 `生成诊断`，查看建议如何落到 `SectionPatch`。
4. 点击 `预览改动` 和 `应用到草稿`，确认草稿改动和发布隔离。
5. 点击 `测试原版和新版`，查看 control 和 variant 的完整 props。
6. 在公开页提交表单或结账，观察访客分流和事件采集。
7. 回后台查看实时事件流、指标卡片和实验转化。
8. 点击 `模拟 1000 位访客`，观察后台任务和实时刷新。
9. 点击实验 `完成`，选择一个胜出版本应用到草稿。
10. 点击 `发布`，再点击 `对比` 查看快照差异。
11. 需要验证恢复能力时，对历史快照点击 `回滚`。

## 代码入口

继续看代码时，可以从这几个文件追核心链路：

- `app/services/events/ingestion_service.rb`
- `app/services/events/payload_fingerprint.rb`
- `app/services/events/metadata_sanitizer.rb`
- `app/services/analytics/aggregation_service.rb`
- `app/services/experiments/lifecycle_service.rb`
- `app/services/experiments/assignment_service.rb`
- `app/services/sites/snapshot_service.rb`
- `app/controllers/public/checkouts_controller.rb`
- `app/controllers/public/form_submissions_controller.rb`
- `app/views/public/sites/show.html.erb`

## 本地环境提示

- 如果页面没有样式，可以执行 `bin/rails tailwindcss:build`。
- 如果实时刷新不明显，可以直接查看 `Event`、`EventRollup` 和 `Analytics::AggregationService`，确认后端数据链路。
- 如果实验按钮不可用，通常表示该建议或区块已有未结束实验，这对应同一区块实验锁定规则。
- 如果要查看公开页访客分流信息，可以用 `DEMO_DEBUG=true bin/dev` 启动本地服务。
