# LaunchPulse

LaunchPulse 是一个用 Rails 8 做的全栈作品集项目，方向是“网站发布之后的增长控制台”，不是建站编辑器本身，也不是准备直接商用的生产平台。

这个项目的目标是如何把 Rails 单体项目从数据模型、事务边界、后台任务、实时更新、前端交互到测试交付串成一条完整产品链路。它不追求覆盖真实 SaaS 的全部复杂度，而是把最能体现工程判断的边界做清楚、跑通、测住。

LaunchPulse 关注的是页面发布之后那段更麻烦的事：站长怎么知道页面有没有带来转化、哪块内容该改、改完是不是真的有用、测试跑完了结果又怎么落回正式页面。这几步串不起来的话，前面做得再好看也没意义。

比起单看页面能不能点击，这个项目更值得看的地方是：链路是否完整、数据边界是否清楚、异常路径是否可验证、代码后续是否还能继续扩展。

## 项目亮点

- Rails 8 单体承载公开站点、后台控制台、事件 API、后台任务、实时看板和管理工作流。
- `PublishedSnapshot` 把公开页面和后台草稿隔离，避免未发布内容提前流出。
- 事件入口使用站点令牌、幂等键、payload 指纹和事务边界，避免重复上报、错内容复用和漏斗断层。
- A/B 实验保存原版本和建议版本的完整渲染数据，后续发布不会污染正在运行的实验基线。
- 转化归因按显式实验、区块、通用转化分层处理，避免把一次转化算到无关实验上。
- Solid Queue 负责事件聚合和流量模拟，Solid Cable 把聚合结果实时推到控制台。
- 发布快照带校验和，支持差异对比和安全回滚。
- 测试覆盖核心业务边界，`bin/check-demo` 可一键完成测试、自动加载检查、样式构建和交付包验证。

## 要解决的问题

很多小商家都会遇到同一件事：网站上线之后基本就是凭感觉改。

举几个例子：

- 咖啡店不知道首页那个按钮文案到底有没有带来预约。
- 在线课程搞不清价格区块是不是让人犹豫了。
- 小电商不确定商品区点击量和结账转化之间是不是被某个区块影响了。

LaunchPulse 想把这几件事接成一条闭环：

1. 公开站点只渲染已发布的版本，草稿不会提前流出去。
2. 后台可以对页面区块跑一次审计，给出结构化的建议。
3. 建议能落成一个区块补丁，可以预览、应用、也能回滚。
4. 补丁可以直接拿去开 A/B 实验，原版本和推荐版本都会保留下来。
5. 公开页面按访客做稳定分流，浏览、点击、表单、结账这些行为都会记事件。
6. 后台任务把事件聚合起来，再实时推到控制台。
7. 实验跑完，可以应用推荐版本，也可以明确说原版本更好、不采纳。
8. 最后把草稿发布成一个不可变快照，需要的话能对比差异、能回滚。

## 几个工程细节

- 公开页面读的是 `PublishedSnapshot`，不是后台正在编辑的草稿——发布和草稿是分开的。
- 实验创建的时候，原版本和推荐版本会各自保存一份完整渲染数据，后续再发布页面也不会影响正在跑的实验。
- 商品区的结账不会算到价格区的实验头上，表单提交也不会被错误地记到第一个碰到的实验。
- 事件接口的幂等键如果换了请求内容会被拒绝，不会静默地把新内容吞掉。
- 草稿区块、已回滚的区块，不能再继续给实验数据“投票”。
- 结账那条链路里，订单、点击事件、转化事件是同一个事务，要么一起成功要么一起回滚。
- 发布快照带校验和，回滚前会先核对一遍，历史版本被动过手脚就不让回滚。
- 看板数据来自后端事件聚合，聚合完成后再通过实时通道推给页面。

## 技术栈

- Ruby 4.0.5
- Rails 8.1
- PostgreSQL
- Hotwire（Turbo、Stimulus、Turbo Streams）
- Tailwind CSS
- Solid Queue 跑后台任务
- Solid Cable 做跨进程的实时更新
- RSpec、FactoryBot、Capybara 写测试

用 Rails 单体而不是拆前后端，是因为这个项目的复杂度本来就集中在业务状态、事务、后台任务和实时更新上，不在前端状态管理。把公开站点、后台、事件接口、任务和实时刷新都放同一个工程里，路径短，看代码也更方便。

## 文档

`readme/` 目录下是中文说明：

- [产品概览](readme/00-overview.md)
- [演示流程](readme/01-demo-flow.md)
- [系统架构](readme/02-architecture.md)
- [增长闭环](readme/03-growth-loop.md)
- [数据模型与归因](readme/04-data-model-and-attribution.md)
- [公开站点与事件接口](readme/05-public-runtime-and-event-api.md)
- [发布与实验系统](readme/06-publishing-and-experiments.md)
- [运行与质量保障](readme/07-running-and-quality.md)
- [限制与后续路线](readme/08-limitations-and-roadmap.md)
- [技术摘要](readme/09-technical-summary.md)
- [演示指南](docs/demo-guide.md)
- [技术问答](docs/technical-qa.md)
- [提交说明](docs/submission-note.md)
- [Events API 简表](docs/api-events.md)

这些文档大致是按“产品问题 -> 设计取舍 -> 代码落点 -> 怎么验证”写的。不熟 Rails 也能先从产品链路看懂价值，想深挖再顺着文档里提到的服务对象和测试文件去翻代码。

如果时间有限，建议先看 [技术摘要](readme/09-technical-summary.md)，然后直接看这三个文件：

- `app/services/experiments/lifecycle_service.rb`
- `app/services/analytics/aggregation_service.rb`
- `app/services/events/ingestion_service.rb`

## 本地运行

```bash
bundle config set --local path vendor/bundle
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/dev
```

第一行会把依赖安装到项目内的 `vendor/bundle`，避免写入系统或 Homebrew 的 Ruby gem 目录。这个目录会被 `.gitignore` 和打包脚本排除。

生产 Docker 部署只设置 `DATABASE_URL` 也可以运行：primary 使用 URL 中的数据库，cache、queue、cable 会在同一 PostgreSQL 服务上分别派生为 `<primary>_cache`、`<primary>_queue`、`<primary>_cable`。也可用 `CACHE_DATABASE_URL`、`QUEUE_DATABASE_URL`、`CABLE_DATABASE_URL` 覆盖为其他独立数据库。`bin/rails db:prepare` 会分别准备四套 migration history；数据库角色需有 `CREATEDB` 权限，或提前创建这四个数据库。完整变量和进程说明见[运行与质量保障](readme/07-running-and-quality.md#部署要点demo)。

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

三个站点分别对应本地门店、在线课程、轻电商这几类常见场景。

## 建议怎么看

1. 登录后台，任选一个站点。
2. 看站点详情页：左边区块树，中间实时预览，右边是建议和实验。
3. 点 `生成诊断` 生成建议。
4. 预览一下补丁，再应用到草稿。
5. 从补丁创建实验，确认原版本和推荐版本都保存下来了。
6. 打开对应的公开页面，提交个表单或者点一下结账。
7. 回后台看实时事件流和指标有没有变化。
8. 点 `模拟 1000 位访客`，让后台任务批量生成访客数据。
9. 完成实验，选应用推荐版本，或者保留原版本。
10. 发布当前草稿，打开差异页面看看改了什么。
11. 执行一次回滚，确认历史版本能恢复回来。

这条路径基本覆盖了项目的核心能力：智能建议、结构化补丁、实验分流、事件采集、转化归因、实时分析、发布快照、版本回滚。

## 关键代码位置

- `app/services/ai/growth_audit_service.rb` — 生成确定性的增长建议
- `app/services/experiments/lifecycle_service.rb` — 实验创建、暂停、完成、应用胜出版本
- `app/services/experiments/assignment_service.rb` — 按访客做稳定分流
- `app/services/events/ingestion_service.rb` — 外部事件接口，令牌校验、幂等、归因
- `app/services/analytics/aggregation_service.rb` — 聚合事件、记录转化
- `app/services/analytics/dashboard_broadcaster.rb` — 实时刷新后台看板
- `app/services/sites/snapshot_service.rb` — 发布、差异对比、回滚
- `app/services/sites/published_runtime.rb` — 公开页面读取已发布版本
- `app/controllers/public/checkouts_controller.rb` — 商品和价格方案的演示结账
- `app/views/public/sites/show.html.erb` — 公开页面渲染入口

## 测试和检查

一键跑完：

```bash
bin/check-demo
```

单独跑：

```bash
bundle exec rspec
bundle exec rubocop
bundle exec brakeman --no-pager
bundle exec bundler-audit
bin/importmap audit
```

测试主要盯着这几处容易翻车的边界：

- 公开页面不会渲染草稿。
- 实验原版本不会因为后续发布悄悄漂移。
- 隐藏区块不能再给实验产生归因数据。
- 幂等键对应的内容变了会被拒绝，而不是静默返回旧结果。
- 一个转化不会被算到无关的实验上。
- 订单和转化事件保持事务一致。
- 快照回滚前会校验完整性。
- 从跑审计到创建实验这条用户路径能走通。

## 打包

```bash
bin/package-demo
```

打包脚本会把 `.git`、`tmp`、`log`、`storage`、本地依赖缓存、生成的资产还有 `config/master.key` 都排除掉，压缩包里只留代码、配置、测试和文档。

请用 `bin/package-demo` 生成交付包，不要直接用 Finder 或系统文件管理器压缩整个项目目录。直接压缩容易把 `.git`、`__MACOSX`、日志、缓存或本地存储一起带进去。

`readme/` 下的文件名使用 ASCII，内容仍然是中文。这样在不同系统和解压工具里更稳，不会因为 zip 文件名编码问题影响阅读。

## 当前限制

演示能力和生产能力没有混在一起：

- 智能建议是确定性输出，不调用外部模型。
- 结账只创建演示订单，没接真实支付。
- 实验统计是透明的近似值，不是完整的统计平台。
- 权限系统还比较简单。
- 事件接口目前是单条写入，已有 Rack::Attack 应用层基础限流；生产通过 SolidCache::Store 保存计数，连接同一 cache DB 的多个实例已共享限流状态。生产化还需批量上报、采样、网关/边缘限流、共享存储高可用与容量治理、租户级配额和监控。

详细说明看 [限制与后续路线](readme/08-limitations-and-roadmap.md)。
