# 运行与质量保障

这里说明项目怎么跑、怎么检查，以及测试主要保护了哪些业务边界。

## 本地运行

```bash
bundle config set --local path vendor/bundle
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/dev
```

第一行会把依赖装到项目内的 `vendor/bundle`，避免写入系统或 Homebrew 的 Ruby gem 目录。`vendor/bundle` 是本地依赖缓存，打包时会排除。

登录：

```text
demo@launchpulse.test / password
```

公开站点：

```text
/s/neighborhood-coffee
/s/studio-sprint-course
/s/clearleaf-skincare
```

如果想看公开页的访客分流信息，可以这样启动：

```bash
DEMO_DEBUG=true bin/dev
```

公开页右下角会显示访客短 ID 和当前实验版本。这个只是本地排查用，不是产品核心功能。

## 生产环境注意

- `config.force_ssl` / `assume_ssl` 已开启；健康检查 `/up` 不强制 HTTPS 跳转。
- 设置 `APP_HOST`（如 `demo.example.com`）以启用 Host 授权。
- CSP 当前为 **report-only**，避免 demo 部署被过严策略打断。
- 访客/会话 cookie 在 production 带 `secure`。

## 数据库

项目使用 PostgreSQL，并使用 Rails 8 的多数据库配置：

- 主业务库；
- 缓存库；
- 任务队列表；
- 实时通道表。

`bin/rails db:prepare` 会准备这些结构。

后台任务使用 Solid Queue，实时刷新使用 Solid Cable。这样本地 `bin/dev` 里即使网页进程和任务进程分开，后台任务发出的刷新消息也能被浏览器收到。

## 一键检查

```bash
bin/check-demo
```

这个脚本会跑：

```bash
bin/rails db:test:prepare
bundle exec rspec
bin/rails zeitwerk:check
bin/rails tailwindcss:build
bin/package-demo
```

也就是说，它不仅跑测试，还会确认自动加载、样式构建和打包流程。

## 额外检查

```bash
bundle exec rubocop
bundle exec brakeman --no-pager
bundle exec bundler-audit
bin/importmap audit
```

这些检查分别覆盖：

- Ruby 代码风格；
- Rails 常见安全风险；
- Ruby 依赖漏洞；
- 前端导入依赖漏洞。

## 测试不是只测成功路径

测试重点覆盖了容易让项目“看起来能跑但数据不可信”的地方。

### 公开页面

- 公开页面只渲染已发布快照。
- 后台草稿不会提前出现在公开页。
- 实验原版本使用创建实验时保存的数据。
- 页面浏览会记录分配版本，但不直接归因到某个实验。
- 隐藏区块不能继续接收公开事件。

### 表单和结账

- 动态表单字段能正确渲染和提交。
- 字段展示名变化不影响提交 key。
- 商品展示名变化不影响结账 key。
- 商品结账会创建订单、订单项、点击事件和订单事件。
- 价格方案结账会创建订单和转化事件。
- 如果事件创建失败，订单会回滚。

### 事件接口

- 站点令牌无效会被拒绝。
- 事件类型、来源、设备会校验。
- 附加数据过大、过深、key 太多会被拒绝。
- 幂等键对应不同请求内容会被拒绝。
- 隐藏区块不能通过接口创建实验归因。

### 实验和归因

- 同一个访客稳定分到同一个版本。
- 权重分配可测试。
- 显式归因只记到指定实验。
- 区块归因只记到对应区块实验。
- 无法明确归因的通用转化不会改写事件本身。
- 重复聚合不会重复创建转化。

### 发布和回滚

- 发布会生成快照。
- 差异页面能展示改动字段。
- 原始数据格式的差异仍然可用。
- 回滚前会校验快照。
- 校验失败不会 500，而是给出提示。

### 用户流程

系统测试覆盖了从智能审计到创建实验的完整路径，确保不是只有底层服务能跑，页面操作也能串起来。

## 打包

```bash
bin/package-demo
```

打包会排除：

- `.git`
- macOS 多余文件；
- 临时目录；
- 日志；
- 本地上传存储；
- 本地依赖缓存；
- 生成后的前端资产；
- `config/master.key`

这样生成的压缩包适合直接交付，不会夹带本地缓存或密钥。

请用 `bin/package-demo` 生成交付包，不要直接用 Finder 或系统文件管理器压缩项目目录。系统压缩经常会把 `.git`、`__MACOSX`、日志、缓存、本地存储一起带进去，也会让包体积明显变大。

## 迁移质量

涉及历史数据回填的迁移使用匿名模型，只依赖当时的表结构，不依赖当前 `Product`、`FormField`、`Section` 这些业务模型。这样未来模型新增验证或回调时，老迁移也不会被新业务规则拖坏。

## 常见问题

### 数据库连不上

先确认 PostgreSQL 正在运行，再执行：

```bash
bin/rails db:prepare
```

### 页面没有样式

执行：

```bash
bin/rails tailwindcss:build
```

### 实时看板不刷新

确认已经准备数据库，并且使用 Solid Cable。异步内存通道不能跨网页进程和任务进程。

### Ruby 版本不对

查看：

```bash
ruby -v
cat .ruby-version
```

使用 `.ruby-version` 指定版本后重新安装依赖。
