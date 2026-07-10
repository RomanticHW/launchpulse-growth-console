# 项目范围与交付说明

## 产品范围

LaunchPulse 是一套可运行的网站增长管理原型，覆盖页面分析、内容调整、A/B 实验、访客事件、转化归因、实时看板和版本发布。

项目使用 Rails 8 单体架构，同时提供后台控制台、公开站点、Events API、后台任务和实时更新。公开站点只读取已发布版本，后台草稿不会直接影响访客页面。

当前版本用于本地体验和技术验证，不包含以下生产能力：

- 拖拽式页面编辑器和完整素材管理；
- 真实支付、退款和订单状态管理；
- 企业级团队协作和细粒度权限；
- 严格的实验统计和人群定向；
- 大规模批量事件采集与数据仓库同步；
- 多页面公开站点和自定义域名管理。

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
demo@launchpulse.test
password
```

公开站点：

```text
/s/neighborhood-coffee
/s/studio-sprint-course
/s/clearleaf-skincare
```

## 检查命令

```bash
bin/check-demo
```

该命令依次运行测试、自动加载检查、样式构建和交付包校验。

其他检查：

```bash
bundle exec rubocop
bundle exec brakeman --no-pager
bundle exec bundler-audit
bin/importmap audit
```

## 交付包

```bash
bin/package-demo
```

打包脚本会排除以下本地内容：

- Git 数据和本地工作树；
- 日志、缓存和临时文件；
- 本地上传文件；
- Bundler 依赖缓存；
- 编译后的前端资源；
- `config/master.key`；
- 测试覆盖率等本地检查产物。

脚本完成后会再次检查压缩包条目，发现受限文件时直接失败。

## 数据说明

仓库中的账号、站点、访客、联系人和订单均为示例数据。三个公开站点的品牌、用户反馈和商业内容只用于展示页面结构与业务流程，不代表真实经营主体。

`模拟 1000 位访客` 只生成分析事件，不会为每次模拟转化创建联系人、表单提交或订单。通过公开页面实际提交表单或选择商品、课程方案时，系统会创建对应的示例业务记录。

## 部署说明

项目提供 Dockerfile，也可以按普通 Rails 应用部署。生产模式至少需要配置：

- `SECRET_KEY_BASE`
- `DATABASE_URL`
- `APP_HOST`
- Web 进程
- Solid Queue 工作进程
- Solid Cable 使用的数据库

正式部署前还需要完成密钥轮换、权限审核、监控告警、备份恢复和滥用防护等工作。
