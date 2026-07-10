# LaunchPulse

LaunchPulse 是一套面向网站运营场景的增长管理应用，用于管理页面版本、查看访问与转化数据、生成页面优化建议，并通过 A/B 实验验证改动效果。

项目同时提供后台控制台和公开站点。运营人员在后台调整草稿、创建实验并发布版本；访客在公开站点产生浏览、点击、表单提交和订单等事件；后台任务负责聚合数据并实时更新看板。

当前仓库是一套可以完整运行的产品原型，适合本地体验和技术验证。它尚未接入真实支付、外部页面导入和完整的企业权限体系，不应直接作为生产环境 SaaS 部署。

## 核心功能

- 站点与结构化页面区块管理。
- 草稿预览、页面分析和优化建议。
- 建议改动的预览、应用、撤回与忽略。
- 基于页面区块的 A/B 实验和稳定访客分流。
- 页面浏览、按钮点击、表单提交和订单事件采集。
- 转化归因、实时事件流和指标看板。
- 发布版本、内容差异对比和历史版本恢复。
- 带签名令牌、幂等键和请求指纹的 Events API。

## 主要流程

```text
页面分析 -> 优化建议 -> 内容预览 -> 应用到草稿
-> 创建实验 -> 采集访客事件 -> 查看实验结果
-> 采用实验版本 -> 发布 -> 对比或恢复历史版本
```

页面区块是建议、实验和归因共同使用的业务单位。每个区块都有稳定标识，因此页面发布、访客事件和历史版本之间可以保持一致关联。

公开站点只读取最新发布版本，不会直接展示后台草稿。实验创建时会保存原始版本和优化版本的完整区块数据，后续发布不会改变正在运行的实验内容。

## 技术栈

- Ruby 4.0.5
- Rails 8.1
- PostgreSQL
- Hotwire（Turbo、Stimulus、Turbo Streams）
- Tailwind CSS
- Solid Queue
- Solid Cable
- RSpec、FactoryBot、Capybara

Rails 单体同时承载后台、公开站点、事件接口、后台任务和实时更新。核心业务规则集中在服务对象中，控制器主要负责认证、参数处理和响应。

## 本地运行

```bash
bundle config set --local path vendor/bundle
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/dev
```

第一行会把依赖安装到项目内的 `vendor/bundle`，避免写入系统或 Homebrew 的 Ruby gem 目录。这个目录会被 `.gitignore` 和打包脚本排除。

生产 Docker 部署只设置 `DATABASE_URL` 也可以运行：primary 使用 URL 中的数据库，cache、queue、cable 会在同一 PostgreSQL 服务上分别派生为 `<primary>_cache`、`<primary>_queue`、`<primary>_cable`。也可用 `CACHE_DATABASE_URL`、`QUEUE_DATABASE_URL`、`CABLE_DATABASE_URL` 覆盖为其他独立数据库。`bin/rails db:prepare` 会分别准备四套 migration history；数据库角色需有 `CREATEDB` 权限，或提前创建这四个数据库。完整变量和进程说明见[运行与质量保障](readme/07-running-and-quality.md#生产环境配置)。
登录账号：

```text
demo@launchpulse.test
password
```

示例站点：

```text
/s/neighborhood-coffee
/s/studio-sprint-course
/s/clearleaf-skincare
```

三个站点分别模拟社区咖啡店、在线课程和基础护肤品牌。

如需在公开页查看访客编号和实验分配信息，可以使用调试模式启动：

```bash
DEMO_DEBUG=true bin/dev
```

## 功能体验

1. 登录后台并打开任意站点。
2. 点击 `分析页面`，查看与具体区块关联的优化建议。
3. 预览建议内容，再应用到草稿。
4. 从优化建议创建对照实验。
5. 打开公开站点，提交表单或选择商品、课程方案。
6. 返回后台查看事件流、指标和实验数据。
7. 在实验数据满足判断条件后结束实验，并采用其中一个版本。
8. 发布当前草稿，在版本记录中查看内容差异或恢复历史版本。

`模拟 1000 位访客` 用于快速生成分析数据。模拟任务只创建访客事件，不会批量生成联系人、表单提交或订单等业务记录。

## 文档

- [产品概览](readme/00-overview.md)
- [功能体验流程](readme/01-demo-flow.md)
- [系统架构](readme/02-architecture.md)
- [页面优化与实验流程](readme/03-growth-loop.md)
- [数据模型与转化归因](readme/04-data-model-and-attribution.md)
- [公开站点与事件接口](readme/05-public-runtime-and-event-api.md)
- [发布与实验管理](readme/06-publishing-and-experiments.md)
- [运行、部署与质量检查](readme/07-running-and-quality.md)
- [当前限制与后续规划](readme/08-limitations-and-roadmap.md)
- [技术摘要](readme/09-technical-summary.md)
- [功能体验指南](docs/demo-guide.md)
- [Events API](docs/api-events.md)
- [技术问答](docs/technical-qa.md)
- [项目范围与交付说明](docs/project-scope.md)

## 关键代码

- `app/services/ai/growth_audit_service.rb`：根据页面区块生成结构化优化建议。
- `app/services/experiments/lifecycle_service.rb`：管理实验创建、暂停、结束和结果应用。
- `app/services/experiments/assignment_service.rb`：为访客稳定分配实验版本。
- `app/services/events/ingestion_service.rb`：处理外部事件认证、幂等和归因。
- `app/services/analytics/aggregation_service.rb`：聚合事件并记录转化。
- `app/services/sites/snapshot_service.rb`：发布版本、对比差异和恢复历史内容。
- `app/services/sites/published_runtime.rb`：读取公开站点使用的已发布内容。

## 测试与检查

完整检查：

```bash
bin/check-demo
```

该命令会运行 RSpec、Zeitwerk 检查、Tailwind 构建和交付包校验。

其他检查：

```bash
bundle exec rubocop
bundle exec brakeman --no-pager
bundle exec bundler-audit
bin/importmap audit
```

测试重点覆盖草稿隔离、实验基线、事件幂等、区块可见性、转化归因、事务一致性和版本恢复等业务边界。

## 打包

```bash
bin/package-demo
```

脚本会排除 Git 数据、本地工作树、临时文件、日志、上传文件、本地依赖缓存、构建产物和密钥，并对压缩包内容进行二次检查。

## 当前限制

- 页面分析由固定规则生成，不调用外部模型服务。
- 商品和课程方案只创建示例订单，不处理真实支付。
- 实验结果使用近似统计，只适合观察趋势。
- 权限仅覆盖 `owner`、`marketer` 和 `viewer` 三类基础角色。
- Events API 以单条写入为主，尚未提供批量采集和完整可靠消息机制。
- 公开站点当前只开放首页路径。

- 事件接口已有 Rack::Attack 应用层基础限流；生产通过 Solid Cache 共享计数，仍需网关限流、容量治理、租户配额和监控。

详细范围见[当前限制与后续规划](readme/08-limitations-and-roadmap.md)。
