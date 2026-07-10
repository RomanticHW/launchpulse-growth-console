# Events API

`POST /api/v1/events` 用于接收外部页面或系统上报的访客事件。接口使用站点追踪令牌认证，不依赖后台登录会话。

## 请求

```http
POST /api/v1/events
Content-Type: application/json
```

### 字段

| 字段 | 必填 | 说明 |
|------|------|------|
| `site_token` | 是 | 后台生成的签名站点令牌 |
| `event_type` | 是 | 事件类型，必须在 `Event::TYPES` 中 |
| `visitor_id` | 是 | 调用方提供的稳定访客标识 |
| `session_id` | 否 | 会话标识 |
| `source` | 否 | 访问来源，默认 `direct` |
| `device` | 否 | 设备类型，默认 `desktop` |
| `page_path` | 否 | 页面路径，默认 `/` |
| `section_uid` | 否 | 最新发布版本中的区块 `uid` |
| `experiment_id` | 条件必填 | 与 `variant_key` 同时提供 |
| `variant_key` | 条件必填 | 与 `experiment_id` 同时提供 |
| `occurred_at` | 否 | ISO 8601 时间；格式无效时使用当前时间 |
| `idempotency_key` | 否 | 业务幂等键 |
| `metadata` | 否 | JSON 对象，受大小和深度限制 |

常用事件类型：

- `page_view`
- `cta_click`
- `form_start`
- `product_view`
- `checkout_click`

`form_submit` 和 `order_created` 属于受控转化事件，公开页面不能通过普通事件接口直接伪造。外部 Events API 当前仍允许持有有效站点令牌的调用方上报这些事件；生产部署应根据调用方身份进一步限制。

## 示例

```json
{
  "site_token": "signed-token",
  "event_type": "page_view",
  "visitor_id": "visitor-123",
  "session_id": "session-123",
  "source": "search",
  "device": "mobile",
  "page_path": "/",
  "section_uid": "section-uuid",
  "idempotency_key": "event-123",
  "metadata": {
    "campaign": "summer"
  }
}
```

## 成功响应

```http
HTTP/1.1 202 Accepted
```

```json
{
  "id": 123,
  "status": "accepted"
}
```

使用相同幂等键和相同内容重复请求时，接口返回已有事件编号。

## 错误响应

| HTTP | 场景 |
|------|------|
| `401 Unauthorized` | 站点令牌无效、过期或对应密钥已停用 |
| `422 Unprocessable Content` | 字段缺失、枚举无效、元数据不合法、区块未发布、实验版本无效或幂等冲突 |
| `429 Too Many Requests` | 请求超过限流阈值 |

幂等键对应不同内容：

```json
{
  "error": "idempotency key payload mismatch"
}
```

请求过于频繁：

```json
{
  "error": "rate_limited",
  "message": "请求过于频繁，请稍后重试。",
  "retry_after": 42
}
```

限流响应同时包含 `Retry-After` 响应头。

## 实验归因

1. 同时提供 `experiment_id` 和 `variant_key` 时，使用显式归因；
2. 只提供 `section_uid` 时，使用该区块的实验分配；
3. 已暂停或已结束的实验只复用历史分配，不为新访客创建分配；
4. 实验结果应用后，不再为该实验写入新的转化。

## 相关代码

- `app/controllers/api/v1/events_controller.rb`
- `app/services/events/ingestion_service.rb`
- `app/services/events/metadata_sanitizer.rb`
- `app/services/events/payload_fingerprint.rb`
- `spec/requests/api/v1/events_spec.rb`
