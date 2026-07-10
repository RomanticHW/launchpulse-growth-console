# 运行、部署与质量检查

## 本地运行

```bash
bundle config set --local path vendor/bundle
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/dev
```

登录账号：

```text
demo@launchpulse.test / password
```

公开站点：

```text
/s/neighborhood-coffee
/s/studio-sprint-course
/s/clearleaf-skincare
```

查看访客编号和实验分配信息：

```bash
DEMO_DEBUG=true bin/dev
```

## 本地进程

`bin/dev` 会启动：

- Web：Rails 应用；
- CSS：Tailwind 监听与构建；
- Jobs：Solid Queue 工作进程。

Web 与 Jobs 必须连接到同一套 Solid Cable 数据库，否则后台任务完成后页面无法收到实时更新。

## 数据库

项目使用 PostgreSQL 和 Rails 8 多数据库配置：

- 主业务库；
- 缓存库；
- 任务队列库；
- 实时通道库。

初始化或更新结构：

```bash
bin/rails db:prepare
```

## 生产环境配置

| 变量 | 用途 |
|------|------|
| `RAILS_ENV=production` | 启用生产模式 |
| `SECRET_KEY_BASE` | 会话、签名 Cookie 和站点令牌 |
| `DATABASE_URL` | PostgreSQL 主库连接 |
| `APP_HOST` | Host 授权白名单 |
| `RAILS_LOG_LEVEL` | 日志级别，默认 `info` |

生产环境已启用 SSL 假设与强制跳转；健康检查 `/up` 不执行 HTTPS 跳转和 Host 校验。访客与会话 Cookie 在生产环境使用 `secure` 属性。

内容安全策略当前使用 report-only 模式，部署前应根据实际静态资源和脚本来源调整并验证。

## 部署进程

| 进程 | 职责 |
|------|------|
| Puma | 后台、公开站点和 API |
| Solid Queue Worker | 事件聚合、访客模拟和延迟看板刷新 |
| Solid Cable | 跨进程实时更新 |

小流量环境可以配置 Solid Queue 与 Puma 同进程运行；常规部署建议保留独立工作进程。

## 上线前检查

1. 使用独立的 `SECRET_KEY_BASE`，不要复用开发环境密钥。
2. 设置 `APP_HOST`，并确认反向代理传递 `X-Forwarded-Proto`。
3. 准备主库、缓存库、队列库和 Cable 数据库。
4. 启动 Solid Queue 工作进程。
5. 确认后台可登录，公开站点只展示已发布内容。
6. 验证 Events API 限流和站点令牌轮换。
7. 配置数据库备份、日志收集和监控告警。

## 检查命令

完整交付检查：

```bash
bin/check-demo
```

包含：

```bash
bin/rails db:test:prepare
bundle exec rspec
bin/rails zeitwerk:check
bin/rails tailwindcss:build
bin/package-demo
```

完整 CI 检查：

```bash
bin/ci
```

`bin/ci` 运行 RSpec、RuboCop、bundler-audit、importmap audit 和 Brakeman。GitHub Actions 将测试、代码风格和安全检查拆成并行任务。

## 测试范围

### 公开站点

- 只渲染已发布内容；
- 草稿不会提前展示；
- 实验版本内容保持稳定；
- 未发布区块不能继续产生实验数据。

### 表单与订单

- 动态字段渲染和提交；
- 展示名称修改不影响稳定字段键；
- 订单与事件保持事务一致；
- 商品和课程方案校验所属区块。

### Events API

- 站点令牌认证；
- 事件枚举和元数据限制；
- 幂等键与请求指纹；
- 并发冲突处理；
- 请求限流。

### 实验与归因

- 稳定访客分流；
- 版本权重；
- 显式、区块和通用转化归因；
- 重复聚合保护；
- 实验状态和并发锁。

### 发布与恢复

- 连续版本号；
- 内容差异；
- 校验和；
- 区块稳定标识；
- 未处理实验的恢复限制。

## 打包

```bash
bin/package-demo
```

压缩包会排除：

- `.git` 和本地工作树；
- macOS 附加文件；
- 临时目录、日志和上传文件；
- 本地依赖缓存；
- 生成后的前端资源；
- 密钥和测试覆盖率文件。

脚本会再次检查压缩包条目，发现受限内容时返回失败。

## 常见问题

### 数据库连接失败

确认 PostgreSQL 正在运行，并执行：

```bash
bin/rails db:prepare
```

### 页面没有样式

```bash
bin/rails tailwindcss:build
```

### 实时看板不更新

确认 Solid Queue 工作进程正在运行，并检查 Web 与 Jobs 是否连接同一套 Cable 数据库。

### Ruby 版本不一致

```bash
ruby -v
cat .ruby-version
```

切换到 `.ruby-version` 指定版本后重新安装依赖。
