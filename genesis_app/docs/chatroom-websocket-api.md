# Chatroom WebSocket API

本文档按 `/Users/ionix/Downloads/frontend-location-message-tick-debug(2).md`、`/Users/ionix/Downloads/aitown-chat-ws(1).yaml`、`/Users/ionix/Downloads/2026-07-27-image-message-support.md`、`/Users/ionix/Downloads/0803接口.md` 与 `/Users/ionix/Downloads/waiting-conversation-round-client-guide.md` 更新。V2 部分是新版客户端的权威契约；后半部分保留旧 WS 协议，供版本降级和本地适配使用。

## V2 协议选择

WebSocket Gateway 根据最终握手 Header `x-app-version` 为整条连接选择协议：

| Header 值 | WS 协议 |
| --- | --- |
| 空值、非法版本、`<=0.3.3` | legacy |
| 有效版本 `>0.3.3`，包括 `0.3.4-rc` | V2 |

Flutter 在 Gateway signer 完成后，以不区分大小写的方式读取最终 Header。连接建立后，`ChatroomSession.protocolVersion` 固定不变；同一 socket 不混合解析 legacy 与 V2 envelope。

风险与发布要求：

- 不能只修改 Dart 包版本或请求头 provider；生产 Gateway signer 必须把真实安装包版本写入 `X-App-Version`。
- `app-version` 与 `x-app-version` 不是同一个 Header。旧的 `app-version` 不会选择 V2。
- 空值和拼写错误会静默选择 legacy，造成新版上行 payload 被当成旧结构。联调时必须同时检查握手 Header 和第一条 `join` 原始帧。
- 安装包版本变化需要冷启动新建 socket。热重载或复用旧 session 不能证明 V2 已生效。
- V2 HTTP `/aitown-chat/api/v2/messages` 不读取版本 Header，始终返回 V2 DTO；legacy HTTP `/aitown-chat/api/messages` 保持不变。

## V2 统一 envelope

```json
{
  "type": "user",
  "stream_type": "",
  "ts": 1786340797200,
  "world_id": "world_001",
  "location_id": "loc_2_2_2",
  "session_id": "sess_001",
  "global_message_id": 8703,
  "message_id": 102,
  "location_message_id": 30,
  "conversation_round_id": 7360,
  "sender_type": "user",
  "sender_id": "char_1",
  "sender_name": "Alice",
  "user_id": "user_1",
  "client_msg_id": "client_002",
  "message_type": "text",
  "min_app_version": 0,
  "created_at": "2026-08-10 11:06:37",
  "current_time": "Day 1, 13:50",
  "payload": {
    "content": "Hello"
  },
  "err_no": 0,
  "err_msg": ""
}
```

字段规则：

- `type` 是业务类型；落库内容使用 `user`、`character`、`narrator`、`tick` 等值。
- `stream_type` 是独立路由轴，只允许 `""`、`llm_stream_start`、`llm_chunk`、`llm_stream_end`。解析时必须先路由 `stream_type`，再路由 `type`。
- V2 ID 使用全称 `global_message_id/message_id/location_message_id`。旧别名只存在于 legacy adapter。
- `current_time` 是消息产生时的世界时间元数据，位于顶层；客户端暂时兼容旧数据放在 `payload.current_time` 的情况。
- 元数据位于顶层，业务正文、Tick 内容和流式 `seq/content` 位于 `payload`。
- `payload`、整数 `err_no` 和字符串 `err_msg` 是统一字段。未知扩展字段可以忽略，但 payload 非 object、未知 `stream_type` 或未知业务 `type` 是单帧协议错误。
- Flutter 的共享 wire DTO 是 `ChatroomV2Message.fromJson/toJson`；HTTP 与 WS 应复用它，避免丢失 `type/stream_type/payload` 这三个持久化标记。

## V2 客户端上行

所有 V2 上行都包含 `type/stream_type/ts/client_msg_id/payload/err_no/err_msg`。`join`、`send_message` 和 `user_enter_location` 还包含 `world_id`。

`join`：

```json
{
  "type": "join",
  "stream_type": "",
  "ts": 1786340797000,
  "world_id": "world_001",
  "client_msg_id": "client_001",
  "payload": {"location_id": "loc_2_2_2"},
  "err_no": 0,
  "err_msg": ""
}
```

`send_message`：

```json
{
  "type": "send_message",
  "stream_type": "",
  "ts": 1786340797001,
  "world_id": "world_001",
  "client_msg_id": "client_002",
  "payload": {"content": "Hello"},
  "err_no": 0,
  "err_msg": ""
}
```

`user_enter_location` 不返回 ACK，但仍生成 `client_msg_id`：

```json
{
  "type": "user_enter_location",
  "stream_type": "",
  "ts": 1786340797002,
  "world_id": "world_001",
  "client_msg_id": "client_003",
  "payload": {"location_id": "loc_2_2_2"},
  "err_no": 0,
  "err_msg": ""
}
```

`heartbeat` 与 `leave` 不带 `world_id`，使用空 payload：

```json
{
  "type": "heartbeat",
  "stream_type": "",
  "ts": 1786340797003,
  "client_msg_id": "client_004",
  "payload": {},
  "err_no": 0,
  "err_msg": ""
}
```

## V2 ACK 与 canonical echo

```json
{
  "type": "ack",
  "stream_type": "",
  "ts": 1786340797100,
  "world_id": "world_001",
  "session_id": "sess_001",
  "client_msg_id": "client_002",
  "payload": {},
  "err_no": 0,
  "err_msg": ""
}
```

V2 ACK 只表示服务端收到并受理了对应命令。客户端内部 API 语义如下：

- `ChatroomSession.sendMessage` 保持返回 `Future<ChatroomAck>`，该 Future 只由顶层 `client_msg_id` 匹配的 ACK 完成。
- `ChatroomAck` 是 receipt-only；其可靠字段是 `clientMsgId/code/codeMsg/ts` 以及 session/world 等诊断字段。即使异常服务端 ACK 携带消息 ID，V2 adapter 也不把它们当成 canonical 元数据。
- 随后 `type=user` 的广播才是可落库、带 message/location/round ID 的 canonical echo。它不能提前完成 V2 ACK Future。
- UI/service 如需“已送达”和“已形成正式消息”两个阶段，应分别等待 ACK receipt 与 canonical echo；两者通过 `client_msg_id` 关联。
- 只有明确的 legacy adapter 允许旧 `user_message` echo 代替缺失 ACK，或对无 `client_msg_id` 的特定旧错误码做唯一 pending-send 回退。

## V2 内容与 Tick

非流式内容按 `type` 路由：

- `user` -> `ChatroomUserMessage`
- `character` 或 `narrator` -> `ChatroomNarratorMessage`，同时保留原始 `businessType`
- `tick` -> `ChatroomTickAdvanceMessage`

普通 typed message 保留 `businessType/streamType/minAppVersion/rawPayload`。地点级 Tick 另暴露 `v2TickPayload` 与 `isV2LocationTick`；`ChatroomV2TickPayload` 保存 `current_time/tick_no/sub_tick_no/global/story_events/characters_moved`，也支持历史纯文本 `payload.content` 回退。`tick_no=0` 和 `sub_tick_no=0` 都是有效值，不能用正数判断字段是否存在。

V2 只把地点级 `type=tick` 当作 canonical Tick：

- `global_message_id`：LocationMessage 自身 ID
- `message_id`：world 级消息 ID
- `location_message_id`：地点分页游标
- `conversation_round_id`：本次 Tick/P1I 对话轮次

## V2 LLM 流与错误隔离

LLM 流的外层 `type` 仍表示发送者业务类型，状态只看 `stream_type`。例如 `type=character, stream_type=llm_chunk` 必须解析为 chunk，而不是完整 character message。

活跃流以 `world|location|conversation_round_id|sender_id` 为主要身份；session 用于进一步隔离，`message_id` 只作辅助，因为 V2 流帧允许缺少 ID：

- chunk/end 提供的非空字段必须与 start 兼容。
- 精确字段越多，匹配优先级越高；同 round 不同 sender 不得串流。
- 缺少 round/message ID 时，只允许归并到唯一候选。
- 多个候选同分时发出 `stream_ambiguous`，保留全部流且不写入任何候选，避免静默串流。
- 正序 `seq` 被去重；乱序 chunk 暂存，直到缺口补齐后按序发布。stream end 的完整 `content` 是最终权威文本。

任何单帧 JSON、字段、type 或 stream_type 解析错误只产生 `protocol_error`，不能关闭 socket，也不能阻止下一帧正常交付。

## V2 保留的控制事件

以下控制通知保留既有外层 `type` 与业务 payload：`tick_start`、`tick_done`、`world_change`、`user_location_change`、`world_new_message`、`map_updated`、`character_updated`、`new_user_join`、`balance_low`。`user_enter_location/story_events/characters_moved` 的既有通知/正式消息适配也继续存在。

`balance_low` 的 Gems 余额只使用 `payload.balance_cent`。该字段必须是 JSON 整数 cent；缺失或类型不合法时，本帧按协议错误隔离。业务模型保存原始 cent，用户可见余额由统一 Gems 格式化工具转换为固定一位小数。

V2 地点聊天不跟随控制通知中的 legacy `detail_url`：`world_new_message` 或 `characters_moved` 带 `location_id` 时只调用 `/aitown-chat/api/v2/messages` 刷新该地点；缺少地点时对当前世界的叶子地点做限并发 V2 刷新。这条 runtime 链路不调用 `/aitown-chat/internal/world/messages` 或 legacy `/aitown-chat/api/messages`。

### Go On：创建新的续写轮次

2026-09-08：依据 `go-on-client-guide.md`。`ChatroomSession.goOn(locationId, sourceConversationRoundId, clientMsgId)` 只在已认证 V2、成功 join 目标地点后发送一次：

```json
{"type":"go_on","world_id":"world_001","client_msg_id":"go-on-001","payload":{"location_id":"loc_001","source_conversation_round_id":101}}
```

来源轮次为正整数 int64，不能放在外层 `conversation_round_id`；请求不带 content、message、card_id 或操作者 UID。请求 ID 必须非空，不能重复占用在途 ID。最新来源、本人归属、Tick 与计费资格由后端校验，客户端接口不判断按钮状态。

```json
{"type":"ack","world_id":"world_001","location_id":"loc_001","conversation_round_id":102,"client_msg_id":"go-on-001","payload":{"billing":{"price":1,"price_cent":120,"pricing_version":"round_v3"}},"err_no":0,"err_msg":""}
```

成功返回 `ChatroomGoOnReceipt`，包含世界、地点、来源轮次、新轮次、请求 ID 和可选 `ChatroomRoundBilling`。匹配世界/地点并验证新轮次后，ACK 即完成 Future；不等待用户消息回显或三层正式消息 ID。`receiptConversationRoundId` 与历史消息元数据分开，不改变 `hasCanonicalMessageMetadata`。billing 不要求候选专用 status；缺失价格不补造，精确费用取 price_cent（示例 1.20 Gem），接口不刷新或增减钱包。

**Go On 的 client_msg_id 不提供业务幂等。** ACK 超时、发送异常、断线均返回异常且绝不自动重发/重连补发；超时代表结果不明，不能据此判断服务器未受理。迟到 ACK 仍通过 events 暴露。后续业务恢复须按新轮次查询历史，无 ACK 时没有按请求 ID 查询受理结果的接口。本次不加入自动查询或恢复记录。

正式 waiting/character/narrator/end 事件按世界、地点、新轮次正常分发，可能先于 ACK 到达。`llm_stream_end` 只结束一条消息，`end_conversation_round.err_no=0` 也不保证整轮已成功持久化。接口不创建 Go On 用户气泡，不拼装候选到正式历史。

V2 `type=error` 解析为 `ChatroomErrorEvent`，保留 world/location/round/user/client 请求上下文、数值 `errNo` 及兼容字符串 `code`。入队前失败为错误 ACK；ACK 后的 error 可能没有 client_msg_id，依靠新轮次关联。保留所有服务端错误码，不用英文提示文本作为枚举；仅 end 或流中断也不代表可自动重试。

### LLM 轮次卡片命令与私有事件

2026-09-08：依据 `llm-round-cards-client-guide.md` 1.1 版。本次只接入协议能力，不加入重生成按钮、自动选卡、候选拼装、轮询或本地待提交记录；服务端部署状态需另行联调确认。

仅支持 V2（合法 `x-app-version > 0.3.3`），复用当前已认证连接。最新完成轮次、轮次发起人、次数上限和计费资格由服务端校验。

```json
{"type":"regenerate_llm_card","world_id":"world_001","conversation_round_id":7358,"client_msg_id":"regen-7358-1","payload":{"location_id":"loc_1"}}
{"type":"select_llm_card","world_id":"world_001","conversation_round_id":7358,"client_msg_id":"select-7358-1","payload":{"location_id":"loc_1","card_id":9902}}
```

`ChatroomSession.regenerateLlmCard` 要求当前已加入目标地点；`selectLlmCard` 允许补报旧地点。两者要求调用方提供 1～128 字符幂等 ID，禁止重复占用在途请求 ID；不会自动重发，调用方负责用同一 ID 恢复请求。
不携带操作者 UID，也不提供 HTTP 重生成接口。

成功 ACK 保持 receipt-only，不带正式消息三层 ID。`ChatroomAck.receiptConversationRoundId` 保存受理轮次（`cardConversationRoundId` 保留兼容别名），`regeneration` / `selection` 是独立类型，`hasCanonicalMessageMetadata` 不因此变为 true。

- `ack.payload.regeneration`：`conversation_round_id`、`original_card_id`、`card_id`、`generation_state`、`billing`，失败已有候选还可包含 `error`。ACK 成功仅表示受理/恢复已有状态，不代表生成成功。
- `ack.payload.selection`：与 HTTP select 的 `ChatroomCardSelection` 完全相同，含最终卡和刷新范围。接口仅返回结果，未接业务刷新或自动确认。
- 错误 ACK 保留现有 `ChatroomFailureEvent` code/message/clientMsgId/requestType，不当作候选成功。

候选流：

```json
{"type":"llm_card_stream","stream_type":"chunk","world_id":"world_001","location_id":"loc_1","conversation_round_id":7358,"global_message_id":8701,"user_id":"user_001","sender_type":"character","sender_id":"char_1","sender_name":"Alice","payload":{"card_id":9902,"card_message_index":1,"seq":1,"content":"Hello","current_time":"Day 1, 12:00"},"err_no":0,"err_msg":""}
```

`ChatroomLlmCardStream` 只接受 start/chunk/end；卡内序号从 1 开始，chunk 必须有正数 seq，content 是增量，end 是该条完整正文。与普通 `llm_stream_*` 路由隔离，每条候选携带正整数 `global_message_id`，从 start 到最终采用保持稳定；不携带正式 `message_id/location_message_id`。候选不进入正式队列、持久化缓存或现有 AI 流拼装，也不发送客户端 ACK。当前仅分发事件，未来业务层按 `(card_id, global_message_id, seq)` 去重、按固定 `card_message_index` 排序，不能使用数组下标定位编辑目标。

整张卡终态：

```json
{"type":"llm_card_generation_end","stream_type":"","world_id":"world_001","location_id":"loc_1","conversation_round_id":7358,"user_id":"user_001","payload":{"card_id":9902,"generation_state":"succeeded","billing":{"status":"committed","price_cent":180,"pricing_version":"round_v3"}},"err_no":0,"err_msg":""}
```

`ChatroomLlmCardGenerationEnd` 只接受 succeeded/failed；失败保留 payload.error、外层错误号和信息。单条流 end 不等于整卡成功。私有事件在 session 按世界、用户隔离，可通过 events 或 ChatroomMessageHandlers 的 onLlmCardStream/onLlmCardGenerationEnd 消费。

generation_state：preparing / queued / generating / succeeded / failed。
billing.status：not_required / not_started / reserved / committed / cancelled；price_cent 为整数 cent 或 null，pricing_version 原样保存。原卡 not_required 不表示原始消息免费。ACK、终态模型不推算费用，不进行预占、结算或退款。

断线不迁移/重播私有流，恢复依赖 GET /cards；后续业务需按指南实现退避查询、待确认记录及固定卡触发。目前没有自动重生成、后台轮询、自动选卡或新消息拦截。
确认产生的 conversation_range_updated 继续使用既有正式历史范围刷新机制；候选事件自身不触发该机制。

### `conversation_range_updated`（批量编辑 / 删除）

2026-09-08：批量 POST 成功后，无论纯编辑、纯删除或混合操作，统一向同世界、地点的 V2 连接广播一次，包含操作人。新接口不再发送 `llm_message_updated`。客户端保留旧编辑事件解析仅作旧版本通知兼容；新批量链路不依赖它。

```json
{"type":"conversation_range_updated","stream_type":"","ts":1788854400000,"world_id":"world_001","location_id":"loc_2_2_2","payload":{"start_conversation_round_id":7358,"end_conversation_round_id":7362,"newest_message_id":84},"err_no":0,"err_msg":""}
```

此事件是控制通知，不携带正文或删除列表，不追加普通气泡、不进入流式拼装、不发送客户端 ACK；`ts` 不作为版本号。

- HTTP 成功响应和 WS 通知共用范围刷新流程，重复通知合并；操作端在漏广播时仍可通过 HTTP 返回范围刷新。
- 收到范围后废弃旧历史请求与分页状态；从 `since=0, limit=100` 开始，携带原闭区间，以已返回的最小正 `location_message_id` 前翻，直到 `has_more=false`，游标不前进视为失败。
- 新范围到达时取消旧请求、合并未完成范围并重拉；全部页成功后在内存与 SQLite 原子替换闭区间，空结果也清除旧消息，范围外保留。失败不提交部分结果，保留待刷新范围。
- 消息按稳定全局 ID 去重、按新地点序号排序。地点最新序号允许降低到 0，不复用世界 `lastMessageId`。SQLite 沿用版本 4 和每地点 200 条上限，写入按地点串行。
- 初始化、补洞、缓存读取和翻页受请求代次保护；活跃流式缓存独立，完成事件与刷新协调，旧历史响应不得覆盖新内容。
- 加入、重连或显式 `refreshLocationHistory` 从最新页重建最多 200 条缓存。网络写入结果不明时先刷新确认，不自动重发整批。
- 编辑状态 `status=20` 由服务端保存，历史不包含该状态；客户端不新增已编辑视觉标记。

### `waiting_conversation_round`

普通 `send_message` 或 `user_enter_location` 自动触发 P3 时，Chat 服务在处理本轮消息前发送以下 V2-only 控制事件：

```json
{
  "type": "waiting_conversation_round",
  "stream_type": "",
  "ts": 1785890000000,
  "world_id": "world_001",
  "location_id": "loc_001",
  "conversation_round_id": 301,
  "payload": {},
  "err_no": 0,
  "err_msg": ""
}
```

客户端按 `location_id` 保存等待中的 `conversation_round_id`，并同时禁用该地点的 Send 按钮和发送/重试入口。该事件不渲染气泡、不写入消息缓存。用户主动发送从调用 `send_message` 时立即锁定并启动 30 秒兜底；服务端主动 P3 从收到 waiting 时锁定并启动兜底。同一轮重复 waiting 不重置截止时间。

### `end_conversation_round`

本轮所有普通消息完成后，服务端发送字段与 waiting 对称的结束事件：

```json
{
  "type": "end_conversation_round",
  "stream_type": "",
  "ts": 1785890001000,
  "world_id": "world_001",
  "location_id": "loc_001",
  "conversation_round_id": 301,
  "payload": {},
  "err_no": 0,
  "err_msg": ""
}
```

只有 `err_no=0`、同地点且同 `conversation_round_id` 的 end 可以正常解锁并取消兜底。Character、Narrator、Tick 和 `llm_stream_end` 都不再结束 V2 conversation round。其他地点、旧 round、重复或错误 end 均幂等忽略。30 秒仍未收到匹配 end 时客户端异常兜底解锁；旧 Timer 必须通过 generation 校验，不能清除后续新 round。自动重连保留原绝对截止时间，显式断开或销毁 Service 时清除。

# Legacy WebSocket 适配附录

以下章节描述 `x-app-version` 为空、非法或 `<=0.3.3` 时使用的旧协议。实现入口是 `chatroomLegacyEventFromEnvelope`；不要把旧别名或 ACK echo 回退扩散到 V2 路径。

## 1. 概览

| 项 | 值 |
| --- | --- |
| OpenAPI | `3.0.3` |
| 标题 | `AITown Chat WebSocket API` |
| 版本 | `2.5.0` |
| Dev WS 服务 | `wss://dev.hushie.ai/aitown-chat/ws` |
| Flutter WS 配置 | `GENESIS_CHATROOM_WS_URL` |
| Flutter 默认 WS | `wss://api.worldo.ai/aitown-chat/ws` |
| Flutter HTTP 配置 | `GENESIS_CHATROOM_HTTP_URL` |

建联时服务端自动创建 Session；同一用户建立新连接时，服务端会踢掉该用户的旧连接。客户端需要通过心跳维持连接，当前 Flutter 默认每 2 秒发送一次。所有 WebSocket 消息使用 JSON，字段命名采用 `snake_case`。

世界级广播使用单一世界通道：

```text
channel:chat:world:{world_id}
```

Flutter 侧 WebSocket 域名使用独立配置 `GENESIS_CHATROOM_WS_URL`，不复用 chatroom HTTP 接口的 `GENESIS_CHATROOM_HTTP_URL`。

## 2. 建联接口

```text
GET wss://dev.hushie.ai/aitown-chat/ws?world_id={world_id}
```

请求头：

| 参数 | 必填 | 示例 | 说明 |
| --- | --- | --- | --- |
| `Authorization` | 是 | `Bearer user_token_001` | 用户认证 token |

查询参数：

| 参数 | 类型 | 必填 | 示例 | 说明 |
| --- | --- | --- | --- | --- |
| `world_id` | `string` | 是 | `world_123` | 世界实例 ID |

成功响应：

| 状态码 | 说明 |
| --- | --- |
| `101` | `Switching Protocols`，WebSocket 连接成功 |

## 3. 客户端上行消息

`join`、`send_message`、`heartbeat`、`leave` 的业务字段直接放在顶层；`user_enter_location` 使用客户端通用消息外层，并将地点放在 `payload.loc_id`。

### 3.1 `join`

进入指定地点聊天室。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `type` | `string` | 是 | 固定 `join` |
| `client_msg_id` | `string` | 否 | 客户端消息 ID，用于 ack 匹配 |
| `world_id` | `string` | 是 | 世界实例 ID |
| `location_id` | `string` | 是 | 地点 ID |

```json
{
  "type": "join",
  "client_msg_id": "client_abc_001",
  "world_id": "world_001",
  "location_id": "loc_001"
}
```

### 3.2 `user_enter_location`

显式触发用户进入地点消息。该命令与 `join` 完全独立，不要求固定先后顺序；客户端每次显式地点进入只发送一次，自动重连不补发。命令不携带 `client_msg_id`，服务端成功受理不发送 ACK；Tick 锁定或入场历史规则不满足时可能静默忽略。

```json
{
  "type": "user_enter_location",
  "ts": 1785890000000,
  "world_id": "world_001",
  "payload": {
    "loc_id": "loc_001"
  },
  "err_no": "",
  "err_msg": "",
  "broadcast": false
}
```

### 3.3 `send_message`

发送聊天消息到当前聊天室。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `type` | `string` | 是 | 固定 `send_message` |
| `client_msg_id` | `string` | 否 | 客户端消息 ID，用于 ack 匹配 |
| `content` | `string` | 是 | 消息内容 |

```json
{
  "type": "send_message",
  "client_msg_id": "client_abc_002",
  "content": "大家好！"
}
```

### 3.4 `heartbeat`

心跳消息。

```json
{
  "type": "heartbeat"
}
```

### 3.5 `leave`

离开当前聊天室，保持 WebSocket 连接。

```json
{
  "type": "leave",
  "client_msg_id": "client_abc_003"
}
```

## 4. 服务端下行统一结构

服务端下行消息使用统一顶层结构，公共元数据直接放在顶层，个性化内容放在 `payload`。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `type` | `string` | 是 | 事件类型 |
| `schema_version` | `integer` | 否 | 事件 schema 版本；Flutter 会解析并保留 |
| `event_id` | `string` | 否 | 事件 ID；Flutter 会解析并保留 |
| `ts` | `integer(int64)` | 是 | 毫秒时间戳 |
| `world_id` | `string` | 是 | 世界实例 ID |
| `payload` | `object` | 是 | 个性化消息载荷 |
| `session_id` | `string` | 否 | 会话 ID，排查用 |
| `global_msg_id` | `integer(int64)` | 否 | 全局消息 ID，全局递增 |
| `msg_id` | `integer(int64)` | 否 | 消息 ID，world 级别递增 |
| `location_msg_id` | `integer(int64)` | 否 | 地点消息 ID，location 级别递增；世界级消息为 `0` |
| `conversation_round_id` | `integer(int64)` | 否 | 对话轮次 ID |
| `tick_no` | `integer` | 否 | Tick 序号；既可位于顶层，也兼容从事件 payload 读取 |
| `sub_tick_no` | `integer` | 否 | 当前 Tick 内的子 Tick 序号；与 `tick_no` 组合显示为 `Tick {tick_no}-{sub_tick_no}` |
| `user_id` | `string` | 否 | 用户 ID |
| `sender_id` | `string` | 否 | 发送者 ID |
| `sender_name` | `string` | 否 | 发送者名称 |
| `location_id` | `string` | 否 | 地点 ID |
| `current_time` | `string` | 否 | 世界时间，如 `Day 45, 19:30` |
| `err_no` | `string` | 是 | ack 错误码；成功为空字符串 |
| `err_msg` | `string` | 是 | ack 错误信息；成功为空字符串 |
| `broadcast` | `boolean` | 否 | 是否为世界广播 |

Flutter 解析器忽略 envelope 和 `payload` 中未识别的扩展字段，但不将未知的外层 `type` 当作已知事件处理；该单个事件记录为 `protocol_error` 后丢弃，WebSocket 连接继续。

## 5. 服务端下行消息

### 5.1 `ack`

服务端确认收到客户端消息。正常 ack 的 `err_no` 和 `err_msg` 均为空字符串；错误也统一通过 `type: "ack"` 返回，不再发送 `type: "error"`。

```json
{
  "type": "ack",
  "ts": 1717300000000,
  "world_id": "world_001",
  "session_id": "sess_abc",
  "global_msg_id": 1001,
  "msg_id": 501,
  "location_msg_id": 201,
  "conversation_round_id": 123,
  "err_no": "",
  "err_msg": "",
  "payload": {
    "client_msg_id": "client_abc_002"
  }
}
```

错误 ack 示例：

```json
{
  "type": "ack",
  "ts": 1717300000000,
  "world_id": "world_001",
  "session_id": "sess_abc",
  "err_no": "2006",
  "err_msg": "世界正在推进中，请稍候...",
  "payload": {
    "client_msg_id": "client_abc_002"
  }
}
```

### 5.2 系统通知

这些事件共用 `SystemNotifyPayload`：

| 事件 | 触发时机 | 客户端行为 |
| --- | --- | --- |
| `tick_start` | 外部 tick 服务调用 lock 接口 | 用户不能发送消息，但可以进出 location |
| `tick_done` | 外部 tick 服务调用 unlock 接口 | 用户可以发送消息 |
| `world_change` | Tick 完成后世界发生变更 | 调用 `/api/v1/world/detail?world_id=xxx` 拉取世界详情 |
| `user_location_change` | 玩家 join/leave 或收到 `tick_start` | 调用 `/aitown-chat/api/ulocation?world_id=xxx` 拉取玩家位置 |
| `world_new_message` | 世界某地点产生新对话 | Flutter 忽略 legacy `detail_url`：有 `location_id` 时调用 `/aitown-chat/api/v2/messages` 刷新该地点，无地点时限并发刷新当前世界的叶子地点 |

`SystemNotifyPayload`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `title` | `string` | 标题 |
| `summary` | `string` | 摘要 |
| `detail_url` | `string` | 详情 URL，空字符串表示无详情 |

示例：

```json
{
  "type": "world_change",
  "ts": 1717300000000,
  "world_id": "world_001",
  "payload": {
    "title": "世界变更",
    "summary": "角色位置变更，新玩家加入",
    "detail_url": "/api/v1/world/detail?world_id=world_001"
  }
}
```

`world_new_message` 还会携带顶层 `location_id`。

#### 5.2.1 世界时间线增量事件

| 事件 | 必需字段/载荷 | Flutter 行为 |
| --- | --- | --- |
| `user_enter_location` | 新版正式消息携带正数 `msg_id/location_msg_id`、真实 `location_id/sender_id/user_id` 与 `payload: { content, message_type }` | 转换为正式 `WorldChatroomMessage`，进入地点队列并持久化，同时调用 `/aitown-chat/api/ulocation` 刷新玩家位置；兼容旧 `{ char_id, to_location_id, text }` 通知形态 |
| `story_events` | 顶层 `msg_id > 0`；`payload` 可为 grouped `{ location_id, location_name, paragraphs }`，也可为 flat single-event `{ location_id, timestamp, visibility, visible_to, text, clue }` | 两种形态统一归一化为段落列表，立即转换为正式 `WorldChatroomMessage`，进入地点队列并持久化；后续 HTTP 同 `message_id` 消息替换该项，不重复显示 |
| `map_updated` | `payload: {}` | 递增 `WorldChatroomState.mapUpdatedRevision`，并与同批 `world_change`、`tick_done`、`character_updated` 合并刷新一次 world detail；从 `locations` 中筛选新增 ID、`level=3` 且 `is_new=true` 的项后发布顶部 Push 通知 |
| `character_updated` | `payload: {}` | 与同批 world detail 刷新合并；从 `characters` 中筛选新增 ID 且 `is_new=true` 的项后发布顶部 Push 通知 |
| `characters_moved` | `payload: { movements: [{ char_id, to_loc_id }] }`；正式消息优先携带顶层 `msg_id > 0`，`location_id` 可为空表示世界广播 | 有正式消息 ID 时直接进入 location/world 队列并持久化；空地点广播复制到所有叶子地点。兼容旧 envelope 缺少 `msg_id` 的通知形态：先以临时 ID 立即入队渲染，再通过 HTTP 拉取 canonical 消息原位替换；两种来源共用人物去向气泡 |

grouped 形态的 `story_events.payload.paragraphs[]` 字段：

- `timestamp`: string
- `visibility`: `public` 或 `char_only`
- `visible_to`: string[]；`char_only` 时必须非空
- `text`: string
- `clue`: string

flat single-event 形态直接将同一组 `timestamp/visibility/visible_to/text/clue` 字段放在 `payload` 顶层，不携带 `paragraphs`；客户端将其归一化成 `location_name: ""` 且只包含这一项的段落列表。HTTP `sender_type=story_events` 的 `content` JSON 字符串使用完全相同的两形态兼容规则。

示例：

```json
{
  "type": "story_events",
  "schema_version": 1,
  "event_id": "evt_story_001",
  "ts": 1785890000000,
  "world_id": "world_001",
  "location_id": "loc_station",
  "global_msg_id": 5626,
  "msg_id": 232,
  "location_msg_id": 0,
  "conversation_round_id": 6816,
  "tick_no": 4,
  "sub_tick_no": 1,
  "sender_id": "sub_tick",
  "sender_name": "sub_tick",
  "payload": {
    "location_id": "loc_station",
    "location_name": "旧火车站",
    "paragraphs": [
      {
        "timestamp": "Day 4, 18:46",
        "visibility": "public",
        "visible_to": [],
        "text": "远处传来列车的汽笛声。",
        "clue": ""
      }
    ]
  }
}
```

`story_events.msg_id` 缺失、为 `0` 或负数时，该帧按 `protocol_error` 丢弃，不进入消息队列或持久化。typed payload 格式不合法时同样只丢弃该帧，WebSocket 连接保持可用。

`characters_moved` 携带正数 `msg_id` 时直接作为正式消息处理；顶层 `location_id` 非空时进入该地点，为空时作为世界广播复制到所有叶子地点。兼容旧版仅有 `event_id/ts/world_id/payload` 的通知 envelope：typed payload 校验通过后，客户端先生成仅存在于内存的临时消息并立即加入所有叶子地点队列，再通过 `/aitown-chat/api/v2/messages` 对有地点的通知刷新该地点、对无地点通知限并发刷新叶子地点；canonical 记录按归一化后的 movements payload 原位替换临时项并持久化。V2 地点聊天运行时不调用 internal world messages 或 legacy messages 接口。即使 HTTP 暂时失败，本次 WSS 消息仍会立即显示；`movements[]` typed payload 非法时，该帧按 `protocol_error` 丢弃，连接继续。

HTTP 与 WebSocket 的合法 `characters_moved` 最终使用同一个气泡：标题为“人物去向”，每条 movement 显示“角色名 has gone to 地点名”。地点名可以点击；目标与当前地点不同时，客户端切换到目标地点聊天。V2 Tilemap 会在切换前登记目标地点，关闭目标聊天后重建到承载该地点的父级地图，并将视口聚焦到目标地点。

### 5.3 `tick_advance`

世界时间推进消息。格式与普通内容消息一致，顶层 `current_time` 和 `payload.content` 值相同；`payload.tick_no` 是页面展示的 Tick 编号。历史消息接口中对应 `sender_type: "tick"`，并应携带 `tick_no`。只有该事件投影出的零 `location_msg_id` legacy Tick 继续以 world `msg_id` 作为 supplemental 排序和双游标边界；带正数地点游标的 Tick 与其他 canonical V2 消息完全一样按 `location_message_id` 处理。

```json
{
  "type": "tick_advance",
  "ts": 1780924703973,
  "world_id": "w_4LA63V",
  "global_msg_id": 1001,
  "msg_id": 501,
  "location_msg_id": 0,
  "conversation_round_id": 123,
  "current_time": "Day 45, 19:34",
  "payload": {
    "content": "Day 45, 19:34",
    "tick_no": 7
  }
}
```

### 5.4 `user_message`

广播用户发送的消息给世界内所有用户。

```json
{
  "type": "user_message",
  "ts": 1717300000000,
  "world_id": "world_001",
  "session_id": "sess_abc",
  "global_msg_id": 1001,
  "msg_id": 501,
  "location_msg_id": 201,
  "conversation_round_id": 123,
  "user_id": "user_001",
  "sender_id": "user_001",
  "sender_name": "张三",
  "location_id": "loc_001",
  "payload": {
    "content": "大家好！",
    "client_msg_id": "client_abc_002"
  }
}
```

### 5.5 `nar_new_message`

旁白或角色旁白式消息。`payload` 使用 `UserMessagePayload`，不再使用系统通知 payload。`payload.message_type` 表示内容类型：`text` 为文本，`image` 为图片且 `content` 保存图片 URL。字段缺失时，旧 `sender_id=nar_pic` 消息兼容为 `image`，其他发送方按 `text`；字段存在但为 `null` 或空字符串时按 `text`。

```json
{
  "type": "nar_new_message",
  "ts": 1717300000000,
  "world_id": "world_001",
  "location_id": "loc_001",
  "global_msg_id": 1003,
  "msg_id": 503,
  "location_msg_id": 203,
  "conversation_round_id": 123,
  "sender_id": "nar_pic",
  "sender_name": "Narrator",
  "payload": {
    "content": "https://example.com/images/scene.jpg",
    "message_type": "image"
  }
}
```

该增量只增加 `payload.message_type`，不改变事件名、顶层消息 ID 字段或已有 envelope。Flutter 读取时去除首尾空白并转为小写。只有 `message_type=image` 且 `sender_id=nar_pic` 的消息渲染图片；`image` 但发送方不是 `nar_pic`、以及其他未知非空类型，均保留在消息模型和缓存中但不渲染。

### 5.6 LLM 流式消息

#### `llm_stream_start`

```json
{
  "type": "llm_stream_start",
  "ts": 1717300000000,
  "world_id": "world_001",
  "location_id": "loc_001",
  "global_msg_id": 1002,
  "msg_id": 502,
  "location_msg_id": 202,
  "conversation_round_id": 123,
  "payload": {
    "sender_type": "character",
    "sender_id": "char_001",
    "sender_name": "村长"
  }
}
```

#### `llm_chunk`

```json
{
  "type": "llm_chunk",
  "ts": 1717300000500,
  "world_id": "world_001",
  "location_id": "loc_001",
  "global_msg_id": 1002,
  "msg_id": 502,
  "location_msg_id": 202,
  "conversation_round_id": 123,
  "payload": {
    "sender_type": "character",
    "sender_id": "char_001",
    "sender_name": "村长",
    "seq": 5,
    "content": "欢迎来到"
  }
}
```

#### `llm_stream_end`

```json
{
  "type": "llm_stream_end",
  "ts": 1717300001000,
  "world_id": "world_001",
  "location_id": "loc_001",
  "global_msg_id": 1002,
  "msg_id": 502,
  "location_msg_id": 202,
  "conversation_round_id": 123,
  "payload": {
    "sender_type": "character",
    "sender_id": "char_001",
    "sender_name": "村长",
    "content": "欢迎来到我们的小镇！有什么可以帮助你的吗？"
  }
}
```

`sender_type` 可为 `character` 或 `narrator`。`llm_chunk.payload.seq` 用于排序，防止乱序。

## 6. 配套 HTTP 接口

这些接口由 chatroom 服务提供。Flutter 侧通过 `GenesisApi.chatroomHttp` 访问，base URL 由 `GENESIS_CHATROOM_HTTP_URL` 配置，默认 `https://api.worldo.ai/`。

### 6.1 GET `/api/v1/world/detail`

获取世界详情。该接口由主 HTTP 服务提供，字段以 `docs/apifox-http-api-contract.md` 的 `World detail` 契约为准。

Query：

- `world_id*`: string，世界实例 ID

### 6.2 GET `/aitown-chat/api/ulocation`

获取世界内所有已加入 location 的玩家位置信息，按地点分组返回。未加入任何 location 的用户不会出现在结果中。AI 角色位置仍以 `/api/v1/world/detail` 为准，不在该接口返回。

Query：

- `world_id*`: string，世界实例 ID

响应字段：

- `world_id`: string，世界实例 ID
- `locations`: `{ location_id, users: ChatroomLocationUser[] }[]`
- `users[].user_id`: string，用户 ID
- `users[].user_name`: string，用户显示名
- `users[].avatar`: string，用户头像 URL

响应：

```json
{
  "err_no": 0,
  "err_msg": "",
  "data": {
    "world_id": "world_001",
    "locations": [
      {
        "location_id": "loc_001",
        "users": [
          {
            "user_id": "user_001",
            "user_name": "张三",
            "avatar": "https://example.com/avatar/user_001.jpg"
          }
        ]
      }
    ]
  }
}
```

### 6.3 GET `/aitown-chat/api/messages`

YAML 的 `paths` 写作 `/api/messages`，但通知 `detail_url` 使用 `/aitown-chat/api/messages`，项目实现按 chatroom 服务前缀访问。

Query：

- `world_id*`: string，世界实例 ID
- `location_id*`: string，地点 ID
- `since`: integer，起始消息 ID，`0` 表示获取最新
- `limit`: integer，默认 `20`，最大 `100`

响应消息字段按当前 HTTP 文档的 `MessageDTO`：`global_message_id` 全局递增，`message_id` world 级别递增，`location_message_id` location 级别递增；`sender_type` 取值为 `user`、`character`、`narrator`、`npc`、`tick`、`user_enter_location`、`story_events` 或 `characters_moved`。`user_enter_location.content` 为纯文本入场文案；`story_events/characters_moved.content` 为 JSON 字符串。所有正数 `location_message_id` 均参与地点连续窗口、补洞、分页、本地 key 和去重。零游标 legacy 记录继续兼容入队和展示，但只有 `tick`（旧 `tick_advance` 投影）按 world `message_id` 排序并使用双游标分页/删除；零游标 `user_enter_location/story_events/characters_moved` 不参与 location continuity、gap 或分页边界。`sub_tick_no` 为可选整数；正数时与 `tick_no` 组合显示，例如 `tick_no=4, sub_tick_no=1` 显示为 `Tick 4-1`。`message_type` 取值为 `text` 或 `image`，图片 URL 保存在 `content`。字段缺失时，旧 `sender_id=nar_pic` 消息兼容为 `image`，其他发送方按 `text`；字段存在但为空时按 `text`。只有 `image + nar_pic` 渲染图片，其他图片发送方和未知类型只存储、不渲染。`created_at` 格式为 `2006-01-02 15:04:05`。

响应：

```json
{
  "err_no": 0,
  "err_msg": "succ",
  "data": {
    "messages": [
      {
        "global_message_id": 90001,
        "message_id": 1001,
        "location_message_id": 101,
        "location_id": "loc_001",
        "conversation_round_id": 7001,
        "sender_type": "user",
        "sender_id": "char_user_001",
        "sender_name": "小明",
        "user_id": "u_001",
        "content": "大家好！",
        "message_type": "text",
        "current_time": "Day 1, 08:00",
        "tick_no": 3,
        "created_at": "2026-07-01 10:00:00"
      },
      {
        "global_message_id": 90002,
        "message_id": 1002,
        "location_message_id": 102,
        "location_id": "loc_001",
        "conversation_round_id": 7002,
        "tick_no": 7,
        "sender_type": "tick",
        "sender_id": "tick",
        "sender_name": "Time",
        "user_id": null,
        "content": "Day 45, 19:30",
        "message_type": "text",
        "current_time": "Day 45, 19:30",
        "created_at": "2026-07-01 10:05:00"
      },
      {
        "global_message_id": 90003,
        "message_id": 1003,
        "location_message_id": 103,
        "location_id": "loc_001",
        "conversation_round_id": 7003,
        "tick_no": 7,
        "sender_type": "narrator",
        "sender_id": "nar_pic",
        "sender_name": "Narrator",
        "user_id": null,
        "content": "https://example.com/images/scene.jpg",
        "message_type": "image",
        "current_time": "Day 45, 19:35",
        "created_at": "2026-07-27 10:06:00"
      }
    ],
    "has_more": false,
    "newest_message_id": 1003
  }
}
```

## 7. 状态码与错误码

### 7.1 成功状态

| 场景 | 字段/状态码 | 说明 |
| --- | --- | --- |
| WebSocket 建联 | HTTP `101` | `Switching Protocols`，WebSocket 连接成功 |
| Chatroom HTTP API | HTTP `200` | HTTP 请求成功，业务结果继续看响应体 |
| `/aitown-chat/api/ulocation` | `err_no: 0` | 业务成功 |
| `/aitown-chat/api/messages` | `code: 0` | 业务成功 |
| WebSocket `ack` | `err_no: ""` | ack 成功；`err_msg` 同样为空字符串 |

注意：`ack.err_no` 在当前协议中是 `string`，成功值为空字符串 `""`；HTTP 接口里的 `err_no` 通常是 `integer`，成功值为 `0`。

### 7.2 WebSocket 错误 `1xxx`

| 错误码 | message | 注释 |
| --- | --- | --- |
| `1001` | 参数错误 | 请求参数不正确 |
| `1002` | 消息格式错误 | WebSocket 消息 JSON 格式不正确 |
| `1003` | 未知消息类型 | 发送了不支持的消息类型 |
| `1004` | 已加入聊天室 | 用户已经在当前聊天室中 |
| `1005` | 未加入聊天室 | 用户未加入聊天室，无法发送消息 |
| `1006` | join 消息格式错误 | join 消息 JSON 格式不正确 |
| `1007` | user_id、sender_id、sender_name 必填 | join 消息缺少必填字段 |
| `1008` | send_message 消息格式错误 | send_message 消息 JSON 格式不正确 |
| `1009` | content 必填 | 消息内容不能为空 |
| `1012` | 未建立连接 | WebSocket 连接未建立 |
| `1013` | location_id 必填 | 地点 ID 不能为空 |
| `1014` | 地点不存在 | 该地点不在当前世界中 |
| `1015` | 被踢下线 | 您已在其他设备登录 |

### 7.3 业务错误

| 错误码 | message | 注释 |
| --- | --- | --- |
| `3001` | 余额不足 | 用户余额不足，请充值后重试 |
| `2001` | 创建会话失败 | 创建 Session 时发生错误 |
| `2002` | 生成消息ID失败 | Redis 生成消息 ID 失败 |
| `2003` | 生成轮次ID失败 | Redis 生成轮次 ID 失败 |
| `2004` | 保存消息失败 | 消息持久化失败 |
| `2006` | 世界正在推进中 | Tick 锁定中，请稍候 |
| `2010` | 消息发送过于频繁 | 消息发送过于频繁，请稍后重试 |

注：YAML 中该分组标记为 `业务逻辑错误 (2xxx)`，但包含 `3001` 余额不足，客户端应按具体错误码处理，不只按首位范围判断。

### 7.4 内部错误 `5xxx`

| 错误码 | message | 注释 |
| --- | --- | --- |
| `5000` | 服务暂时不可用 | 内部服务错误 |

### 7.5 认证错误 `100xx`

| 错误码 | message | 注释 |
| --- | --- | --- |
| `10001` | 未授权 | 请先登录 |

## 8. Flutter 实现约定

- `ChatroomClient.connect` 使用 `GENESIS_CHATROOM_WS_URL` 拼接 `world_id` query，并通过 `Authorization: Bearer ...` 建联。
- `join`、`send_message`、`heartbeat`、`leave` 上行消息只使用顶层字段；`join` 只发送 `client_msg_id`、`world_id`、`location_id`。
- `user_enter_location` 使用通用外层和 `payload.loc_id`，不携带 `client_msg_id`、不等待 ACK、不超时重试；只在显式地点进入时发送一次，发送失败不影响 `join` 状态，自动重连不补发。
- `heartbeat` 只发送 `{ "type": "heartbeat" }`，不携带 `client_msg_id`，也不等待 ack。
- 服务端错误只接受 `type: "ack"` 携带 `err_no` / `err_msg`；不兼容旧 `type: "error"` 或 `err_code`。
- `send_message` 的 ack 必须通过 `payload.client_msg_id` 匹配；服务端缺失该字段时请求会超时。
- `join()` 只接受携带相同 `payload.client_msg_id` 的 `ack` 作为完成信号。
- `tick_advance` 会进入所有叶子地点的消息队列，Flutter 展示为系统时间推进提示；`sub_tick_no > 0` 时文案为 `Tick {tick_no}-{sub_tick_no} · {current_time}`，缺少子 Tick 时保持 `Tick {tick_no} · {current_time}`。历史消息里的 `sender_type: "tick"` 同样处理。
- 新版 `user_enter_location` 下行先进入正式地点消息队列、缓存和现有入场气泡，再与旧通知形态一样通过 `/aitown-chat/api/ulocation` 刷新完整玩家位置快照；并发刷新由单 active + trailing 调度合并。
- `story_events` 必须携带正数 `msg_id`，并复用正式消息队列、缓存和 message-id 去重；不创建无 ID 的瞬时消息。WS `payload` 与 HTTP `content` JSON 都兼容 grouped `paragraphs[]` 和 flat single-event，两者归一化后走同一气泡渲染。
- `characters_moved` 有正数 `msg_id` 时直接使用正式消息队列、缓存和 message-id 去重；空 `location_id` 广播到所有叶子地点。旧版缺少 `msg_id` 的 envelope 会先以临时消息立即入队，再通过地点 V2 HTTP canonical 消息同步并原位替换；最终与 HTTP 记录共用可点击地点的人物去向气泡。
- `world_change`、`tick_done`、`map_updated`、`character_updated` 共用单 active 的 world detail 刷新调度；同一事件循环内的通知合并为一次请求，刷新期间的新通知最多触发尾随刷新，不并行请求。
- `map_updated` 仍发布递增 revision 供 Tilemap 刷新；location 只从 detail 的 `locations` 中筛选同时满足“ID 不在刷新前快照中”、S3（优先 `level=3`，缺失时按 location tree depth 判断）且 `is_new=true` 的项，character 继续按“新增 ID 且 `is_new=true`”筛选，生成去重后的顶部 Push 通知。
- `llm_stream_start`、`llm_chunk`、`llm_stream_end` 在 Flutter 内部仍复用 `ChatroomAiMessageStream` 事件模型。
- 原始帧通过 `developer.log(name: 'ChatroomSocketFrame')` 输出到 Flutter DevTools Logging。
