# 技术问答

## 1. 为什么公开站点要读 `PublishedSnapshot`，不直接读当前 `sections`？

后台草稿和公开页面的语义不一样。运营者在后台改文案、预览补丁、调整区块时，不代表这些内容已经可以给真实访客看。公开站点只读最新 `PublishedSnapshot`，可以保证草稿不会提前流出。发布动作会生成一个带版本和 checksum 的不可变快照，后面才能做差异对比和回滚。

## 2. `PublishedSnapshot` 保存哪些内容？

它保存站点信息、页面列表、区块列表、区块类型、区块 uid、props、版本号、发布时间和 checksum。重点不是只存“已发布”状态，而是把当时的结构化页面状态完整保存下来。这样公开运行时、diff 和 rollback 都有同一份可信来源。

## 3. snapshot checksum 解决什么问题？

回滚依赖历史快照。如果历史快照被手动改坏，直接恢复会把错误数据写回草稿。checksum 用来确认快照 payload 没有被篡改或损坏。当前实现使用 canonical JSON 计算 SHA256，避免 Hash key 顺序导致同一内容产生不同校验值。它不是完整安全审计系统，但能保护发布回滚的基本前提。

## 4. 为什么区块要有 uid，而不是只用数据库 id？

数据库 id 只适合当前数据库内部引用，不适合作为长期业务身份。区块可能被重新导入、删除重建、从历史快照恢复，id 会变，但业务上仍然是同一个首屏区块或价格区块。`section.uid` 贯穿发布快照、公开事件、实验绑定、归因和回滚，能让这些模块对同一个区块达成一致。

## 5. `SectionPatch` 为什么要保存 `before_props` 和 `after_props`？

补丁后面会进入实验。如果只保存当前区块状态，过几天再看就说不清当时测试的原版本和建议版本是什么。`SectionPatch` 把修改前和修改后的 props 保存下来，应用、撤回和实验状态变化都不重写这两份证据。这样实验创建时可以稳定生成 control 和 variant。

## 6. control variant props 是怎么来的？

创建实验时，control variant 的 props 优先取 `patch.before_props`，没有补丁时才退回当前 `section.props`。建议版本的 props 优先取 `patch.after_props`，否则用当前 props 合并推荐补丁。这样 control 不是运行时再读当前快照，而是实验创建时固定下来的完整渲染数据。

## 7. 为什么原版本也要保存完整 props？

如果原版本运行时去读当前发布快照，实验跑到一半时后台又发布了新内容，control 就会悄悄变化，实验结果不再可信。保存完整 props 的成本不高，但可以换来稳定实验基线，也方便确认“这次 A/B 到底比较了什么”。

## 8. experiment lifecycle 怎么设计？

当前实验状态比较克制：`active`、`paused`、`completed` 加上胜出版本应用时间。创建实验后进入 active，可以暂停、继续、完成。完成实验只是停止收数，不自动改页面；还需要明确选择 `应用 原版本` 或 `应用 建议版本`。这样“实验结束”和“业务决策”是分开的。

## 9. same-section lock 是为了解决什么？

同一个区块如果同时跑多个未结束实验，公开页按 `section_uid` 分流时会出现歧义，转化归因也说不清该算给哪个实验。所以 `Experiments::LifecycleService` 在创建实验时对 section 加锁，并检查同一区块是否已有 active、paused 或未应用胜出结果的 completed 实验。这个限制牺牲了一点灵活性，但换来清楚的数据口径。

## 10. assignment 为什么不是每次随机？

访客进入同一个实验后应该稳定看到同一版本。当前 `AssignmentService` 基于 experiment id 和 visitor id 做哈希，再按 variant 权重落桶。第一次分配后会写入 `Assignment`，后续直接复用。这样刷新页面不会一会儿看到原版本、一会儿看到建议版本。

## 11. assignment 在事件接口里为什么算副作用？

事件接口如果带 `section_uid`，系统可能会创建一次实验分配。这个分配会影响后续归因，所以它不是无害的临时计算。带幂等键的请求必须先确认没有同 key 不同 payload 的冲突，再创建 assignment 和 event，避免一个最终被拒绝的请求留下分流记录。

## 12. conversion attribution 的优先级是什么？

优先级是显式实验、区块归因、通用转化。显式实验表示事件已经明确带了 experiment 和 variant，只记给这个实验。区块归因根据 `section_uid` 找该区块的活跃实验。没有实验和区块信息时，才看访客已经参加的活跃实验，并且只记给目标匹配的实验。

## 13. 为什么不能把一次转化算到访客参加过的所有实验？

这样图表会变好看，但结论会错。比如访客同时参加首屏、商品区和价格区实验，最后在商品区下单。如果把订单算给所有实验，就无法判断商品区改动是否有效，也会污染首屏和价格区结果。这里选择区块优先，是为了让业务含义更清楚。

## 14. public tracking 做了哪些校验？

公开页事件和外部事件接口都会校验事件类型、来源、设备、metadata，并且如果带了 `section_uid`，会确认这个区块仍在已发布快照里。草稿区块、已回滚或已移除的区块不能继续产生实验数据。公开入口不能假设参数天然可信，即使这些参数通常来自自己渲染的页面。

## 15. 外部事件接口为什么需要 signed site token？

`POST /api/v1/events` 是开放入口，必须知道事件属于哪个站点，也要避免任意伪造 site id。当前实现用 Rails message verifier 签出 site token，再匹配 active `ApiKey` 的 digest。这样接口调用方不直接传数据库 id，也能支持后续 token 轮换和停用。

## 16. idempotency fingerprint 解决什么问题？

只有 idempotency key 不够。调用方可能错误复用同一个 key，但 payload 已经从 `page_view` 变成 `order_created`。如果系统只看 key，就会静默返回旧事件，真实转化丢失。fingerprint 把事件类型、访客、来源、设备、页面、区块、实验、时间和清洗后的 metadata 规范化后计算摘要。同 key 同 payload 返回旧事件，同 key 不同 payload 直接拒绝。

## 17. 为什么幂等处理用了 PostgreSQL advisory lock？

并发请求可能同时带同一个 idempotency key。如果只靠唯一索引，仍然可能在冲突路径里留下 assignment 之类副作用。当前实现对 site 和 idempotency key 计算 lock key，在事务级 advisory lock 里先检查已有事件和 fingerprint，再决定是否创建 attribution、assignment 和 event。这样并发路径和普通路径语义一致。

## 18. metadata sanitizer 的边界是什么？

metadata 顶层必须是对象，内部可以有数组和嵌套对象。清洗器限制总大小、嵌套深度和每层 key 数，把 `ActionController::Parameters` 转成普通 Hash，不支持的对象转成字符串。这样后续聚合能稳定读取 `section_uid`、`form_id`、`product_key` 等字段，也避免异常 payload 把后台任务打断。

## 19. form/checkout transaction，也就是表单和结账事务，怎么处理？

公开表单提交会校验字段，成功后创建联系人、表单提交记录、事件和聚合任务。商品或价格结账会创建订单、订单项、`checkout_click` 和 `order_created` 事件。关键点是业务记录和转化事件在同一事务语义下处理，事件创建失败时订单不应该留下，避免后台漏斗出现“有订单、没事件”的断层。

## 20. `checkout_click` 为什么不作为实验主转化？

`checkout_click` 更像意向或交互事件，不能代表真正转化。商品区和价格区最后都会产生 `order_created`，用订单创建作为主转化更清楚。当前 `Conversion` 只接受 `form_submit`、`order_created` 和 `any_conversion` 这三类口径，点击、浏览可以进入事件流和 rollup，但不写成实验转化。

## 21. Solid Queue 在项目里承担什么？

Solid Queue 负责后台事件聚合和访客模拟任务。公开页或事件接口创建 `Event` 后，统一 dispatcher 会先领取数据库租约，再入队 `AggregateEventJob`。聚合任务更新 rollup、转化记录和 `aggregated_at`；production 另有每 5 分钟运行的恢复任务，重新领取遗漏或租约过期的未聚合事件。这样请求路径不用同步完成所有统计，也避免普通幂等重放反复制造队列项。

## 22. Solid Cable 在项目里承担什么？

Solid Cable 负责把后台任务完成后的数据变化推到控制台。聚合服务完成后，通过 `Analytics::DashboardBroadcaster` 广播实时事件、汇总指标和实验数据。这里的重点是任务进程和网页进程分开时仍能刷新，而不是只靠前端本地状态模拟。

## 23. rollback 的语义是什么？

rollback 不是把数据库整库倒回去，而是把某个快照里的页面和区块结构恢复到当前草稿，再发布为一个新版本。恢复前先校验 checksum，恢复时按 `section.uid` 匹配区块。这样历史版本可以回到正式发布流里，同时保留“这次回滚也是一次新发布”的审计含义。

## 24. 当前版本和生产版本的边界在哪里？

当前版本是可运行的产品工程 demo，不是可直接商用的完整平台。这也是 demo vs production 的主要边界：智能建议是确定性输出，不接外部模型；结账是演示订单，不接真实支付；实验统计是透明近似，不是完整统计平台；权限系统比较简单；事件接口是单条写入并已有 Rack::Attack 应用层基础限流；生产通过 SolidCache::Store 保存计数，连接同一 cache DB 的多个实例已共享限流状态。事件聚合已有租约和周期恢复，但还不是事务 outbox。生产化还需要批量上报、采样、网关/边缘限流、共享存储高可用与容量治理、租户级配额与监控，以及更完整的可靠消息、队列告警和补偿机制。

## 25. 如果进入生产，最先补哪些能力？

优先补五类：真实页面导入和编辑、外部模型接入但保留稳定 fallback、实验曝光和更严谨统计、团队权限和接口密钥治理、事件采集的批量写入和可靠消息机制。这里不会先追求页面数量，而是先把数据可信度、运行可靠性和协作边界补齐。
