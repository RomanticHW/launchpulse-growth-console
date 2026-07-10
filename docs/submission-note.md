# 提交说明

## 项目是什么

LaunchPulse 是一个 Rails 8 全栈产品工程 demo，方向是“网站发布后的增长控制台”。

它是一个作品集项目，不是准备直接商用的生产平台。项目重点是展示从后端工程视角切入 Rails / 全栈开发时，如何把业务状态、事务一致性、异步任务、实时更新、前端交互和测试交付放进同一个可运行系统里。

它围绕一条完整链路展开：

```text
公开站点 -> 访客事件 -> 后台聚合 -> 实时看板
-> 结构化建议 -> 区块补丁 -> A/B 实验
-> 转化归因 -> 应用胜出版本 -> 发布快照 -> 差异对比和回滚
```

项目重点不是做一个全功能建站器，而是说明页面上线之后如何判断效果、如何安全修改、如何验证改动、如何把验证结果回到正式版本。

## 为什么不是建站器复制品

这个项目没有复制任何现有建站产品的界面、文案、品牌表达或拖拽编辑体验。

它选择的是建站产品里发布之后的一段工程问题：

- 公开页面不能读后台草稿。
- 建议要能落成可执行区块补丁。
- 补丁进入实验后，原版本和建议版本要有稳定基线。
- 访客行为要能进入后台统计。
- 表单和订单转化要能归因到正确区块和实验。
- 实验结果要能回写草稿，再通过发布快照进入公开页面。
- 历史版本要能对比和回滚。

这个方向和建站产品相关，但不是复刻建站编辑器。

## 本地运行

推荐使用项目内依赖目录，避免写入系统或 Homebrew 的 Ruby gem 目录：

```bash
bundle config set --local path vendor/bundle
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/dev
```

登录账号：

```text
demo@launchpulse.test
password
```

公开站点示例：

```text
/s/neighborhood-coffee
/s/studio-sprint-course
/s/clearleaf-skincare
```

如果要查看公开页的本地分流调试信息，可以这样启动：

```bash
DEMO_DEBUG=true bin/dev
```

## 检查命令

一键检查：

```bash
bin/check-demo
```

这个脚本会覆盖测试、自动加载检查、Tailwind 构建和打包流程：

```bash
bin/rails db:test:prepare
bundle exec rspec
bin/rails zeitwerk:check
bin/rails tailwindcss:build
bin/package-demo
```

可选的额外检查：

```bash
bundle exec rubocop
bundle exec brakeman --no-pager
bundle exec bundler-audit
bin/importmap audit
```

## 打包方式

使用项目提供的脚本：

```bash
bin/package-demo
```

不要直接压缩整个项目目录。脚本只按 Git 跟踪文件清单读取当前工作树内容，因此已跟踪但尚未提交的修改会进入交付包，未跟踪和已忽略文件不会进入。打包前和生成后还会分别校验清单，拦截环境配置、私钥与证书文件，以及 `.git`、`tmp`、`log`、`storage`、本地依赖缓存、生成资产等本地或内部内容；发现缺失文件、符号链接或受限路径时不会生成交付包。

## 推荐阅读和演示顺序

1. 先读根目录 `README.md`，了解项目定位、运行方式和推荐演示路径。
2. 再读 `readme/09-technical-summary.md`，快速看核心工程边界。
3. 本地跑起来后，登录后台打开 `clearleaf-skincare`。
4. 点击 `生成诊断`，查看结构化建议。
5. 点击 `预览改动`，再点击 `应用到草稿`。
6. 点击 `测试原版和新版`，确认实验里有原版本和建议版本。
7. 点击 `公开预览`，在公开页提交表单，或点击商品 `购买`、价格方案 `选择方案`。
8. 回后台看实时事件、指标和实验数据。
9. 点击 `模拟 1000 位访客`，观察后台任务和实时刷新。
10. 点击实验的 `完成`，再选择 `应用 原版本` 或 `应用 建议版本`。
11. 点击 `发布`，在发布快照区域点击 `对比`。
12. 如需演示恢复，点击历史快照的 `回滚`。

继续看代码时，可以重点看这些文件：

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

## 已知边界

- 智能建议是确定性输出，不调用外部模型接口，目的是保证本地演示和测试稳定。
- 结账只创建演示订单，没有接真实支付。
- 实验统计是透明近似，不替代完整实验平台。
- 账号和权限只覆盖演示所需能力。
- 事件接口当前是单条写入，已有 Rack::Attack 应用层基础限流；生产通过 SolidCache::Store 保存计数，连接同一 cache DB 的多个实例已共享限流状态。生产化还需批量上报、采样、网关/边缘限流、共享存储高可用与容量治理、租户级配额与监控、可靠消息机制。
- 访客模拟只生成分析事件，不创建完整 `Contact`、`FormSubmission`、`Order`、`OrderItem` 业务对象；真实公开表单和公开结账会创建这些记录。
- 当前公开运行时只开放首页 `/s/:slug`，模型保留了页面路径，多页公开站点还需要继续扩展区块可见性判断。
