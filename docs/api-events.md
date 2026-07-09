# Events API（`POST /api/v1/events`）

外部事件入口。认证依赖站点签发的 **site_token**（`MessageVerifier` 签名 + `ApiKey` digest），不使用 Cookie 会话。

## 请求

```http
POST /api/v1/events
Content-Type: application/json
```

### 顶层字段

| 字段 | 必填 | 说明 |
|------|------|------|
| `site_token` | 是 | 后台「生成追踪 token」得到的签名令牌 |
| `event_type` | 是 | 见下方允许类型 |
| `visitor_id` | 是 | 调用方提供的访客标识（稳定字符串） |
| `session_id` | 否 | 会话标识 |
| `source` | 否 | 默认 `direct`；须在 `Event::SOURCES` 内 |
| `device` | 否 | 默认 `desktop`；须在 `Event::DEVICES` 内 |
| `page_path` | 否 | 默认 `/` |
| `section_uid` | 否 | 已发布快照中的区块 uid；用于分流与归因 |
| `experiment_id` | 条件 | 与 `variant_key` 成对出现，显式归因 |
| `variant_key` | 条件 | 与 `experiment_id` 成对出现 |
| `occurred_at` | 否 | ISO8601；非法时按当前时间 |
| `idempotency_key` | 否 | 业务幂等键；同 key 不同 payload 会拒绝 |
| `metadata` | 否 | JSON 对象；经 `MetadataSanitizer` 限制大小/深度 |

### 允许的 `event_type`（节选）

与 `Event::TYPES` 一致，常见：`page_view`、`cta_click`、`form_submit`、`checkout_click`、`order_created` 等。

> Demo 限制：持有有效 token 时可上报转化类事件。生产环境应收紧为服务端签发转化。

## 成功响应

```http
HTTP/1.1 202 Accepted
```

```json
{ "id": 123, "status": "accepted" }
```

幂等重放（同 key 同 fingerprint）仍返回已有事件的 `id`，状态同样为 `accepted`。

## 错误码

| HTTP | 场景 |
|------|------|
| `401 Unauthorized` | `site_token` 无效、过期或对应 ApiKey 已停用 |
| `422 Unprocessable Content` | 缺字段、非法枚举、metadata 不合法、幂等 key 与 payload 指纹不匹配、未发布 section、实验/变体无效等 |
| `429 Too Many Requests` | Rack::Attack 限流；响应 JSON 含 `retry_after`，并带 `Retry-After` 头 |

示例：

```json
{ "error": "idempotency key payload mismatch" }
```

```json
{ "error": "rate_limited", "message": "请求过于频繁，请稍后重试。", "retry_after": 42 }
```

## 归因语义（简）

1. **显式**：`experiment_id` + `variant_key`（实验须为 active，且区块仍在已发布快照中）。
2. **区块**：仅 `section_uid` 时，active 实验会新建分流；paused/completed（未应用胜出）只复用历史 assignment。
3. **聚合**：`AggregationService` 在胜出版本应用后不再写入新的 conversion。

## 相关代码

- `app/controllers/api/v1/events_controller.rb`
- `app/services/events/ingestion_service.rb`
- `spec/requests/api/v1/events_spec.rb`
