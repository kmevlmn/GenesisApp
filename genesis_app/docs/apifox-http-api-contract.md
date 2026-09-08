# Apifox HTTP 接口文档与当前实现差异

来源：
- Apifox 分享页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/460308499e0
- Apifox Origin 模板列表页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/461433666e0
- Apifox Origin 热门标签页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/465715733e0
- Origin detail 增量契约：`/Users/ionix/Downloads/origin_detail_new.md`
- Apifox world tick 页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/462798656e0
- Apifox world tick 列表页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/469083051e0
- World tick 列表增量契约：`/Users/ionix/Downloads/new_tick_list.md`
- Apifox discuss 页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/462474822e0
- Apifox discuss 回复分页页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/466619391e0
- Apifox direct_message 页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/462474827e0
- Apifox direct_message 会话列表页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/462474828e0
- Apifox upload 页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/463764231e0
- Apifox notify 未读数页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/463874827e0
- Apifox notify 通知列表页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/463874828e0
- Apifox notify 标记已读页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/463874829e0
- Apifox search 页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/465724653e0
- Collect 客户端批量上报协议：当前 Flutter 实现
- Report 提交举报：`/Users/ionix/Downloads/report.md`
- Feedback 提交反馈：`/Users/ionix/Downloads/feedback.md`
- Apifox chatroom 获取角色位置列表页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/470909609e0
- Apifox chatroom 世界最近消息页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/465850374e0
- Apifox chatroom 历史消息页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/462446394e0
- Apifox chatroom tick lock 页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/462446395e0
- Apifox chatroom tick progress 页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/462446396e0
- Apifox chatroom tick unlock 页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/462446397e0
- Apifox chatroom narrator write 页：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/462446399e0
- Chatroom 图片消息增量说明：`/Users/ionix/Downloads/2026-07-27-image-message-support.md`
- V2 Origin 完整编辑详情：`/Users/ionix/Downloads/foredit_v2.md`
- 查询我 launch 过的 preset 角色：`/Users/ionix/Downloads/launched.md`
- App 版本升级检查：`/Users/ionix/Downloads/version_check.md`
- Apifox LLM 索引：https://s.apifox.cn/5e96cda4-384c-445a-8cd8-e102f28814ba/llms.txt

提取时间：2026-06-15

图片消息增量核对时间：2026-07-28

World tick 列表增量核对时间：2026-08-05

Origin detail 增量核对时间：2026-08-05

本文档记录 Flutter 项目当前对齐或待替换的 Apifox HTTP 接口，并对比当前 Flutter 项目中的 `lib/network` HTTP 设计。字段后带 `*` 表示 Apifox 标记为必填。

## 总览

本文档当前覆盖 56 个接口，分为 `app`、`用户`、`origin`、`world`、`chatroom`、`search`、`discuss`、`direct_message`、`notify`、`report`、`feedback`、`collect` 和 `upload` 十三组：

| 分组 | 方法 | 路径 | 名称 |
| --- | --- | --- | --- |
| app | POST | `/api/v1/app/version/check` | App 版本升级检查 |
| 用户 | POST | `/api/v1/user/oauth/google` | Google login |
| 用户 | POST | `/api/v1/user/logout` | Logout current session |
| 用户 | POST | `/api/v1/user/delete` | 删除当前账号 |
| 用户 | POST | `/api/v1/user/unfollow` | Unfollow a user |
| 用户 | POST | `/api/v1/user/follow` | Follow a user |
| 用户 | GET | `/api/v1/user/following` | 用户关注列表 |
| 用户 | GET | `/api/v1/user/followers` | 用户粉丝列表 |
| 用户 | GET | `/api/v1/user/info` | user Info |
| 用户 | POST | `/api/v1/user/oauth/apple` | Apple login |
| 用户 | GET | `/api/v1/user/world-history-settings` | 查询当前用户 World History 水位设置 |
| 用户 | PUT | `/api/v1/user/world-history-settings` | 原子更新当前用户 World History 水位设置 |
| 用户 | DELETE | `/api/v1/user/world-history-settings` | 重置当前用户 World History 水位设置 |
| world | GET | `/api/v1/world/list` | World 列表 |
| world | GET | `/api/v1/world/detail` | World 详情 |
| world | GET | `/api/v1/world/map` | 读取 World 2.5D 地图 |
| world | GET | `/api/v1/world/tick/list` | 分页获取 world 下的 tick 列表 |
| world | GET | `/api/v1/world/origin_progress` | 用户在某 origin 下的最大 world tick 进度 |
| world | POST | `/api/v1/world/tick` | world owner 触发一次 tick |
| chatroom | GET | `/aitown-chat/api/ulocation` | 获取角色位置列表 |
| chatroom | GET | `/aitown-chat/internal/world/messages` | 获取世界最近消息 |
| chatroom | GET | `/aitown-chat/api/messages` | 获取旧协议历史消息（兼容/诊断） |
| chatroom | GET | `/aitown-chat/api/v2/messages` | 获取 V2 地点历史消息 |
| chatroom | POST | `/aitown-chat/internal/tick/lock` | 锁定 World |
| chatroom | GET | `/aitown-chat/internal/tick/progress` | 轮询 Tick 进度 |
| chatroom | POST | `/aitown-chat/internal/tick/unlock` | 解锁 World |
| chatroom | POST | `/aitown-chat/internal/narrator/write` | 写入旁白消息 |
| search | GET | `/api/v2/search` | Meilisearch 全局搜索 |
| origin | GET | `/api/v1/origin/list` | Origin 模板列表 |
| origin | GET | `/api/v1/origin/feed` | 按设备去重的 For you 推荐流 |
| origin | POST | `/api/v1/origin/feed/exposure` | 上报 For you 可见项 |
| origin | GET | `/api/v1/origin/hot_tags` | Origin 热门标签 |
| origin | GET | `/api/v1/origin/my_launch_preset_characters` | 查询我 launch 过的 preset 角色 |
| app | GET | `/api/v1/app/config` | App 启动全局配置 |
| origin | GET | `/api/v1/origin/detail` | Origin 模板详情 |
| origin | GET | `/api/v1/origin/map` | 读取 Origin 2.5D 地图 |
| origin | GET | `/api/v2/origin/foredit` | 获取 V2 Origin 完整编辑详情 |
| origin | POST | `/api/v1/origin/launch` | 基于 origin 创建 world |
| discuss | GET | `/api/v1/discuss/list` | 顶级评论分页列表 |
| discuss | GET | `/api/v1/discuss/replies` | 顶级评论下的回复分页列表 |
| discuss | POST | `/api/v1/discuss/post` | 发表评论或回复 |
| discuss | POST | `/api/v1/discuss/delete` | 删除自己的评论或回复 |
| discuss | POST | `/api/v1/discuss/like` | 点赞评论或回复 |
| discuss | POST | `/api/v1/discuss/unlike` | 取消点赞 |
| direct_message | POST | `/api/v1/direct_message/send` | 给指定用户发送私信 |
| direct_message | GET | `/api/v1/direct_message/conversations` | 拉取我的会话列表 |
| direct_message | GET | `/api/v1/direct_message/list` | 拉取与指定用户的消息列表 |
| direct_message | POST | `/api/v1/direct_message/read` | 把与某 peer 的会话标记为已读 |
| direct_message | GET | `/api/v1/direct_message/unread` | 获取我的私信未读总数 |
| direct_message | POST | `/api/v1/direct_message/block` | 拉黑指定用户 |
| direct_message | POST | `/api/v1/direct_message/unblock` | 取消拉黑 |
| direct_message | GET | `/api/v1/direct_message/blocks` | 拉取我的拉黑列表 |
| notify | GET | `/api/v1/message/unread` | 获取消息页未读数 |
| notify | GET | `/api/v1/message/notifications` | 按消息块拉取通知列表 |
| notify | POST | `/api/v1/message/read` | 标记非私信通知已读 |
| report | POST | `/api/v1/report/create` | 提交举报 |
| feedback | POST | `/api/v1/feedback/create` | 提交反馈 |
| collect | POST | `https://collect.worldo.ai/api/v1/collect` | 批量提交客户端行为事件 |
| upload | POST | `/api/v1/upload/image` | 上传图片到阿里云 OSS |

所有 Apifox 200 响应都使用 envelope：

```json
{
  "err_no": 0,
  "err_msg": "succ",
  "data": {}
}
```

## 共享模型

### ImageResource

- `sm_url*`: string，小尺寸图片 URL；旧字符串数据会与 `xl_url` 相同
- `xl_url*`: string，原尺寸图片 URL；旧字符串数据会与 `sm_url` 相同
- `object_key*`: string，原尺寸图片 OSS 对象 key；旧字符串数据为空串

### UserInfo

- `uid*`: string
- `name*`: string
- `avatar*`: string 或 `ImageResource`
- `deleted`: boolean，用户是否已软删除
- `bio`: string
- `last_login_at`: integer，Unix 秒时间戳
- `create_at`: integer，Unix 秒时间戳
- `follower_cnt*`: integer
- `following_cnt*`: integer
- `friend_cnt*`: integer
- `create_origin_cnt*`: integer
- `launch_world_cnt*`: integer
- `join_world_cnt*`: integer

### UserRelation

- `is_self*`: boolean
- `is_followed*`: boolean
- `followed_me*`: boolean
- `is_friend*`: boolean

### DirectMessage

- `msg_id*`: string
- `conv_id*`: string
- `sender_uid*`: string
- `receiver_uid*`: string
- `content*`: string，非空且长度不超过 1000 字符
- `created_at*`: integer，Unix 秒时间戳，示例 `1779539696`

### DirectMessageConversation

- `conv_id*`: string
- `peer*`: UserInfo，对话中的另一方；其中 `last_login_at`、`create_at` 等时间字段均为 Unix 秒时间戳
- `last_message_id*`: string，当前会话最后一条消息 id
- `last_message*`: string
- `last_message_at*`: integer，Unix 秒时间戳，示例 `1797731760`
- `last_sender_uid*`: string
- `unread_cnt*`: integer，当前用户视角下该会话未读数
- `is_friend*`: boolean
- `i_blocked_peer*`: boolean，当前用户是否已拉黑 peer
- `peer_blocked_me*`: boolean，peer 是否已拉黑当前用户
- `can_send_next_message*`: boolean，是否允许当前用户继续发送下一条私信

### MessageNotificationItem

- `notification_id*`: string
- `notice_block*`: string，`world_apply`、`follow` 或 `interaction`
- `notice_type*`: string，`world_apply`、`world_apply_review`、`follow`、`discuss_comment`、`discuss_reply` 或 `discuss_like`
- `sender*`: `UserInfo`
- `biz_type*`: integer
- `biz_id*`: string
- `obj_id*`: string
- `origin_name*`: string，`notice_block=interaction` 时返回，对应评论所在 Origin 名称
- `content*`: string
- `is_read*`: boolean
- `created_at*`: integer，Unix 秒时间戳

### OriginInfo

- `origin_id*`: string
- `origin_name*`: string
- `origin_version*`: string
- `origin_version_time*`: integer，Unix 秒时间戳
- `definition_version*`: integer，地图定义版本；`1` 为旧版地图，`2` 为新版 2.5D 地图
- `owner_uid`: string，创建者 uid，来自登录 session，不接受创建请求覆盖
- `owner_name`: string，创建者昵称
- `brief`: string
- `setting`: string
- `events`: string[]
- `tags`: string[]
- `metric*`: `WorldMetric`
- `created_at`: integer，Unix 秒
- `started_at`: string，故事内起始时间文本
- `tick_duration_days`: integer
- `cover`: string
- `map_url`: string
- `status*`: integer，`10` 正常，`20` tick 中

### OriginStats

- `copy_cnt`: integer
- `discuss_cnt`: integer
- `character_cnt`: integer
- `connect_cnt`: integer
- `location_cnt`: integer
- `max_tick_cnt`: integer

### OriginDetailInfo

`origin/detail` 使用的只读基本信息；它不同于 Create/Update 兼容链使用的 `OriginInfo`，不包含 `setting/events/started_at/tick_duration_days`。

- `origin_id*`: string
- `origin_name*`: string
- `origin_version*`: string
- `origin_version_time`: integer，版本时间 Unix 秒
- `definition_version*`: integer，`1` 为旧版地图，`2` 为新版 2.5D 地图
- `language*`: string，内容语言
- `current_time*`: string，最新 tick 的当前故事时间；尚未 tick 时为空串
- `owner_uid*`: string
- `owner_name*`: string
- `owner_user*`: `UserInfo`
- `brief*`: string
- `tags*`: string[]
- `metric*`: `WorldMetric`
- `created_at*`: integer，Unix 秒
- `cover*`: `ImageResource`
- `map_url*`: string
- `status*`: integer，`10` 正常，`20` 处理中

### WorldInfo

- `world_id*`: string
- `world_name*`: string
- `origin_id`: string
- `origin_version`: string
- `origin_version_time`: string
- `definition_version*`: integer，地图定义版本；`1` 为旧版地图，`2` 为新版 2.5D 地图
- `last_chat_location_id*`: string，`world/detail` 返回当前用户最后聊天的 location ID；没有记录时为空字符串，其他复用 `WorldInfo` 的端点不保证返回。客户端每次进入 World 时用该字段初始化地图和 Location List 的 Recent Message 标签；本次页面会话内发送成功后，再由内存中的临时记录即时覆盖
- `owner_uid`: string，创建者 uid，来自 `tbl_world.owner_uid`
- `owner_name`: string，创建者姓名；用户不存在时为空串
- `brief`: string
- `setting`: string
- `events`: string[]
- `metric`: `WorldMetric`
- `created_at`: integer，Unix 秒
- `last_active_at`: integer，Unix 秒；world 最近一次活跃时间，My Worlds 卡片使用此字段显示时间
- `started_at`: string，故事内起始时间文本
- `tick_duration_days`: integer
- `cover`: string
- `map_url`: string
- `status*`: integer，`10` 正常，`20` tick 中

### WorldMetric

- `mode`: string，例如 `qualitative` 或 `quantitative`
- `label`: string，进度指标名称
- `label_note`: string，指标说明，对应 Basics 表单里的 `Label note`
- `unit`: string，指标单位
- `range`: number[]，指标范围，例如 `[0, 100]`
- `default`: number 或 string，初始值

### WorldStats

- `character_cnt`: integer
- `connect_cnt`: integer
- `location_cnt`: integer
- `tick_cnt`: integer
- `player_cnt`: integer

### WorldOriginProgressResp

- `world_id*`: string，tick 数最大的 world_id；无匹配时为空字符串
- `tick_cnt*`: integer，该 world 的 `current_tick_no`；无匹配时为 0

### Character

- `char_id*`: string
- `type*`: string，`ai` 或 `custom`；origin 模板中固定为 `ai`
- `player_uid*`: string；origin 模板中为空串
- `player_username*`: string
- `player_user*`: `UserInfo`
- `player_joined_at*`: integer，Unix 秒；未绑定玩家时为 `0`
- `name*`: string
- `identity*`: string
- `brief*`: string
- `goal*`: string
- `avatar*`: `ImageResource`
- `initial_location_id*`: string
- `location_id*`: string，当前 location
- `metric_value*`: integer
- `delta*`: integer

`OriginDetailCharacter` 在 `Character` 基础上增加：

- `is_recommend*`: integer，`0` 不推荐、`1` 推荐

### Location

- `location_id*`: string
- `level`: integer，顶层为 `1`
- `location_pid`: string
- `location_name*`: string
- `location_description`: string，仅 world detail 兼容使用；origin detail 不返回
- `location_paragraph`: string，最新段落，每次 tick P1 后可能变化
- `location_timestamp`: string，最新故事时间戳，每次 tick P1 后可能变化
- `location_summary`: string，地点当前摘要，地点列表优先展示
- `image`: string
- `x_percent`: integer
- `y_percent`: integer
- `map_url`: string，当前 location 的地图图片 URL
- `dialogue`: `DialogueLine[]`

### Tick

- `tick_id*`: string
- `tick_no*`: integer
- `sub_tick_no*`: integer，当前 tick 内的子 tick 序号
- `status*`: integer；`20` chat_running、`30` p1_running、`40` p1_done、`50` done、`90` failed，`45` p2_running 仅历史兼容；`GET /world/tick/list` 只返回 `50`
- `tick_result*`: `WorldTickResult`
- `created_at*`: integer，Unix 秒

`WorldTickResult`：

- `current_time*`: string，P1 返回的当前故事时间
- `narrator*`: string
- `paragraphs*`: `TickParagraph[]`
- `location_groups`: `LocationGroup[]`；world tick list 必填，origin detail 不返回

`TickParagraph`：

- `location_id*`: string
- `timestamp*`: string，故事内时间戳，例如 `Day 1, 19:10`
- `text*`: string
- `visibility*`: string，枚举为 `public` 或 `char_only`
- `visible_to*`: string[]；`char_only` 时为可见角色 ID，`public` 时为空数组
- `clue*`: string，为可见角色提供的行动线索或提示
- `character_deltas*`: `CharacterDelta[]`

`CharacterDelta`：

- `char_id*`: string
- `name`: string
- `delta*`: integer，指标增量；prompt 字符串结果由服务端归一为整数

`LocationGroup`（字段均可选）：

- `location_id`: string
- `location_name`: string
- `location_summary`: string
- `characters`: `{ char_id, name }[]`
- `initial_dialogue`: `{ char_id, char_name, name, content }[]`

### ChatroomMessageDTO（旧协议）

- `global_message_id`: integer，全局递增消息 ID
- `message_id`: integer，world 级别递增消息 ID
- `location_message_id`: integer，location 级别递增消息 ID；location 时间线记录可能返回正数或 `0`。正数与普通消息一样参与 location 连续性、补洞和 `since` 游标；零值记录没有 location cursor，必须按下述 legacy 兼容边界处理
- `location_id`: string，地点 ID；世界级消息可能为空
- `conversation_round_id`: integer，对话轮次 ID
- `sender_type`: string，`user`、`character`、`narrator`、`npc`、`tick`、`user_enter_location`、`story_events` 或 `characters_moved`
- `sender_id`: string，发送者 ID
- `sender_name`: string，发送者名称
- `user_id`: string 或 null，用户消息时非空
- `content`: string，普通消息为消息内容；`user_enter_location` 为纯文本入场文案；`story_events`、`characters_moved` 为对应 payload 的 JSON 编码字符串
- `message_type`: string，消息内容类型；`text` 表示文本，`image` 表示图片且 `content` 保存图片 URL。Flutter 读取时去除首尾空白并转为小写；字段缺失时，旧 `sender_id=nar_pic` 消息兼容为 `image`，其他发送方按 `text`；字段存在但为 `null` 或空字符串时按 `text`。只有 `image + nar_pic` 渲染图片，其他图片发送方和未知非空类型保留在消息模型和缓存中但不渲染
- `current_time`: string，世界时间，tick advance 时非空
- `tick_no`: integer，Tick 序号，仅 tick 相关消息时非零
- `sub_tick_no`: integer，可选的子 Tick 序号；正数时 UI 与 `tick_no` 组合显示为 `Tick {tick_no}-{sub_tick_no}`
- `created_at`: string，创建时间，格式为 `2006-01-02 15:04:05`

location 时间线 payload：

- `user_enter_location`: 新版记录直接使用顶层 `sender_id`、`location_id` 与纯文本 `content`；旧 `{ char_id, to_location_id, text }` JSON content 继续兼容
- `story_events` 兼容两种等价形态：
  - grouped：`{ location_id, location_name, paragraphs }`，其中 `paragraphs[]` 为 `{ timestamp, visibility, visible_to, text, clue }`
  - flat single-event：`{ location_id, timestamp, visibility, visible_to, text, clue }`；客户端将其归一化成 `location_name: ""` 且只包含这一项的 `paragraphs[]`
  - 两种形态中的 `visibility` 均为 `public` 或 `char_only`；`char_only` 必须提供非空 `visible_to`
- `characters_moved`: `{ movements }`，其中 `movements[]` 为 `{ char_id, to_loc_id }`

这些记录均可进入 location 本地消息队列。任何带正数 `location_message_id` 的记录都按地点游标维护连续窗口、补洞、`since` 分页、本地 key 和去重。只有遗留零游标 `tick`（`tick_advance` 投影）按 world `message_id` 插入时间线，并在本地分页/旧区段删除时使用配套 world cursor；零游标 `user_enter_location/story_events/characters_moved` 仅作为可展示的兼容记录保留，并可按 `message_id` 后备去重，但不参与 location 连续性、gap、分页边界或 gap 区段删除。服务端单地点响应中的 `location_id` 为空时，客户端使用请求的 `location_id` 分桶。

合法的 `characters_moved` 使用独立人物去向气泡，逐行显示“角色名 has gone to 地点名”；角色或地点名称无法从本地 world 缓存解析时回退到对应 ID。地点名可以点击：目标与当前地点不同时切换到目标地点聊天；V2 Tilemap 同步登记目标地点，使退出聊天后恢复到承载目标地点的父级地图。HTTP 与 WebSocket 来源使用完全相同的 VM、气泡和点击规则。

旧版 WebSocket `characters_moved` envelope 若缺少 `msg_id`，客户端仍会先生成仅存在于内存的临时正式消息并立即加入所有叶子地点队列；随后对有地点的通知请求该地点的 V2 messages，对无地点通知限并发刷新当前世界的叶子地点，并用相同 movements payload 的 canonical `message_id/location_id` 原位替换、持久化该临时项。V2 地点聊天运行时不调用 internal world messages 或 legacy messages 接口。HTTP 暂时失败不会阻止本次 WSS 气泡显示。

旧 `/aitown-chat/api/messages` 返回的 `user_enter_location` 会进入队列、缓存并复用现有入场系统气泡；只有正数 `location_message_id` 参与地点连续性，零游标记录仅展示。其他用户的新入场记录计入新消息提示，当前用户自己的记录仍按通用 self-message 规则排除。

### ChatroomV2MessageDTO

- `type*`: string，业务类型；持久化消息从 `sender_type` 派生。`sender_type=narrator` 时仅 `sender_id=nar/nar_pic` 保持 `narrator`，其他 sender 降级为 `character`；P1/P1I 地点内容为 `tick`
- `stream_type*`: string，非流式消息为空；流式消息为 `llm_stream_start`、`llm_chunk` 或 `llm_stream_end`，与业务 `type` 独立
- `ts*`: integer，毫秒时间戳
- `world_id`、`location_id`、`session_id`: string，消息上下文 ID
- `global_message_id`、`message_id`、`location_message_id`、`conversation_round_id`: integer，完整消息 ID；V2 不使用旧 WS 的缩写 ID 字段
- `sender_type`、`sender_id`、`sender_name`、`user_id`: string，发送者元数据
- `client_msg_id`: string，ACK 关联 ID，位于顶层
- `message_type`: string，`text` 或 `image`
- `min_app_version`: integer，消息最低客户端版本
- `created_at`: string，服务端创建时间
- `payload*`: object，业务字段容器；普通消息内容为 `payload.content`
- `err_no*`: integer，业务错误码；成功为 `0`
- `err_msg*`: string，业务错误信息

`type=tick` 的合法 `payload` 使用 `{ current_time, tick_no, sub_tick_no, global, story_events, characters_moved }`。`story_events[]` 使用 `{ location_id, timestamp, visibility, visible_to, text, clue }`，`characters_moved[]` 使用 `{ char_id, old_loc_id, to_loc_id }`。历史纯文本或服务端无法结构化的 Tick 回退为 `{ content }`。客户端完整保留原始 `payload`，同时解析 typed Tick payload；一个 canonical Tick 只占用自己正数 `location_message_id` 对应的缓存/分页行，派生的 global、story 和 movement 气泡不再各自写入 SQLite 或推进游标。

V2 WebSocket 额外支持 `type=waiting_conversation_round` 控制事件：`stream_type=""`，顶层携带 `world_id/location_id/conversation_round_id`，`payload={}`。客户端按地点禁用 Send 按钮和发送/重试入口，直到 `sender_type=character`、同地点、同 round 且 `streaming=false` 的完整消息到达；流式 start/chunk、其他 sender type、其他地点或其他 round 均不解锁。用户主动发送后建立的 conversation 等待锁使用相同解锁规则。该控制事件不渲染、不落库、无超时和独立 unlock；自动重连期间保留，显式断开时清除。该事件只向最终握手 `x-app-version` 为有效语义版本且 `>0.3.3` 的 V2 客户端发送。

### ChatroomNarratorLocationGroup

- `location_id*`: string
- `location_name*`: string
- `location_summary*`: string
- `characters*`: `{ char_id, name }[]`
- `initial_dialogue*`: `{ char_id, char_name, content }[]`

### DiscussItem

- `discuss_id`: string
- `biz_type`: integer，当前支持 `1` 表示 origin
- `biz_id`: string
- `author`: `UserInfo`
- `content`: string
- `images`: string[]，最多 9 张
- `root_discuss_id`: string，顶级评论为空字符串
- `parent_discuss_id`: string，直接回复目标；顶级评论为空字符串
- `reply_to_uid`: string
- `level`: integer，`1` 顶级评论，`2` 回复
- `reply_cnt`: integer
- `like_cnt`: integer
- `is_liked`: boolean，未登录或未点赞时为 `false`
- `created_at`: string

### UploadImageResult

- `url*`: string，对外可访问图片 URL
- `object_key*`: string，OSS object key，形如 `uploads/20260526/1234567890.jpg`

## 用户接口

### POST `/api/v1/user/oauth/google`

Google 登录。Apifox 未声明鉴权要求。

请求 body：

- `id_token*`: string
- `nonce`: string
- `name`: string，新用户创建时的昵称提示
- `avatar`: string，新用户创建时的头像提示

响应 `data`：

- `token*`: string，session id，同时会通过 `gotea_session` cookie 下发
- `user*`: `UserInfo`
- `relation*`: `UserRelation`

### POST `/api/v1/user/oauth/apple`

Apple 登录。请求和响应结构与 Google 登录一致。

请求 body：

- `id_token*`: string
- `nonce`: string
- `name`: string，新用户创建时的昵称提示
- `avatar`: string，新用户创建时的头像提示

响应 `data`：

- `token*`: string
- `user*`: `UserInfo`
- `relation*`: `UserRelation`

### POST `/api/v1/user/logout`

退出当前 session。

请求 body：无。

响应 `data`：空对象。

### POST `/api/v1/user/delete`

登录用户删除自己的账号。服务端会写入 delete_account 用户日志、删除该 uid 的三方身份绑定，将 `tbl_users.status` 标记为 `2 deleted`，并清理当前 session / active-session / cookie。不清空用户展示资料，不级联删除 origin / world / 评论 / 消息等业务内容。同一个 Google / Apple 账号下次登录时会创建全新的 uid。

请求 body：无。

响应 `data`：空对象。

### GET `/api/v1/user/info`

客户端不使用本接口反查或恢复 UID。当前账号查询前会先校验本地 UID；UID 缺失或为 `guest_` UID 时，直接清除 UID、Token 和缓存用户资料并按未登录处理。启动和会话校验还会同时检查 `auth token`，登录态不完整时同样清理。查看公开用户资料时继续显式传 `uid`。

查询用户信息。`uid` 不传时可理解为当前用户；传入时查询指定用户。

Query：

- `uid`: string

响应 `data`：

- `token*`: string
- `user*`: `UserInfo`
- `relation*`: `UserRelation`

### POST `/api/v1/user/follow`

关注用户，接口幂等。

请求 body：

- `target_uid*`: string，被关注用户 uid

响应 `data`：空对象。

### POST `/api/v1/user/unfollow`

取消关注用户，接口幂等。

请求 body：

- `target_uid*`: string，被取消关注用户 uid

响应 `data`：空对象。

### GET `/api/v1/user/following`

返回 `uid` 关注的用户列表。需登录；任意登录用户均可查询任意 `uid`。

Query：

- `uid*`: string，目标用户 uid
- `pn`: integer，页码，从 1 开始
- `rn`: integer，每页条数，默认 10，最大 100

响应 `data`：

- `total*`: integer
- `pn*`: integer
- `rn*`: integer
- `list*`: `{ user: UserInfo, relation: UserRelation }[]`

### GET `/api/v1/user/followers`

返回关注 `uid` 的粉丝列表。

Query：

- `uid*`: string，目标用户 uid
- `pn`: integer
- `rn`: integer

响应 `data`：

- `total*`: integer
- `pn*`: integer
- `rn*`: integer
- `list*`: `{ user: UserInfo, relation: UserRelation }[]`

### GET `/api/v1/user/world-history-settings`

查询当前登录用户的 World History 水位。响应 `data`：

- `high_watermark*`: integer，当前生效高水位
- `low_watermark*`: integer，当前生效低水位
- `stored_high_watermark*`: integer，持久化高水位；使用默认值时为 `0`
- `stored_low_watermark*`: integer，持久化低水位；使用默认值时为 `0`
- `source*`: string，例如 `default`
- `degraded*`: boolean

### PUT `/api/v1/user/world-history-settings`

原子更新当前登录用户的两个 World History 水位。JSON body 两个字段都必填：

- `high_watermark*`: integer，范围 `20..30`
- `low_watermark*`: integer，范围 `10..20`

响应 `data` 与 GET 相同。

### DELETE `/api/v1/user/world-history-settings`

删除当前用户保存的水位值并恢复服务端默认值。请求 body：无。响应 `data` 与 GET 相同。

## Origin / World 接口

### GET `/api/v1/world/list`

返回 world 列表。world 由 origin 复制而来，列表项只返回 `info + stats`，详情接口返回角色、location、ticks。

Query：

- `pn`: integer，默认 1
- `rn`: integer，默认 10
- `scene`: string，场景；自有数据传 `mine`，指定用户传 `uid`，标签筛选传 `tag`
- `tag`: string，`scene=tag` 时传入标签名
- `origin_id`: string，仅查询基于该 origin 复制出的 world
- `uid`: string，`scene=uid` 时传入目标用户 uid；`scene=mine` 时不传
- `keyword`: string，模糊搜索 `world_name` / `brief`

响应 `data`：

- `total*`: integer
- `pn*`: integer
- `rn*`: integer
- `list*`: `{ info: WorldInfo, stats: WorldStats }[]`

每个 `list[].info` 额外明确包含：

- `definition_version*`: integer，地图定义版本；`1` 为旧版地图，`2` 为新版 2.5D 地图
- `default_map_location_id*`: string，默认展示地图的 location id；`root` 表示根地图

其中 `info.last_active_at` 为 world 最近一次活跃时间（Unix 秒）；My Worlds 卡片时间以该字段为准，不读取 `last_tick.created_at`。

### GET `/api/v1/world/summary/latest`

公开查询同一个 origin 下最新的非空 world summary。调用方可传 `origin_id` 或 `world_id`；传 `world_id` 时服务端先读取该 world 的 `origin_id`，再返回同 origin 下其他 world 的最新 summary，并排除当前 `world_id`。两者都传时，服务端校验 world 所属 origin 与 `origin_id` 一致。结果按 `tick_time DESC, id DESC` 排序，最多返回 5 条，且结果内 `world_id` 不重复。

Query：

- `origin_id`: string，与 `world_id` 至少传一个
- `world_id`: string，传入时会排除该 world 自身

响应 `data`：

- `list*`: `WorldSummaryItem[]`

`WorldSummaryItem`：

- `world_id*`: string
- `origin_id*`: string
- `tick_no*`: integer
- `summary*`: string
- `tick_time*`: integer，summary 对应 tick 的时间，Unix 秒
- `created_at*`: integer，summary 记录创建时间，Unix 秒

错误码：

- `4004`：`origin_id` / `world_id` 都缺失，或二者不匹配
- `20201`：`world_id` 不存在或已软删除

### GET `/api/v1/world/detail`

返回单个 world 的完整详情：基本信息、统计信息、角色列表和 location。`info` 返回 `definition_version` 和当前用户的 `last_chat_location_id`，后者用于客户端进入 World 时初始化 Recent Message 标签；不返回 `tile_types`。主地图及 location 不返回 `map_json`，需要时调用 `/api/v1/world/map`。完整 tick 列表使用 `/api/v1/world/tick/list`。

Query：

- `world_id*`: string

响应 `data`：

- `info*`: `WorldInfo`
- `stats*`: `WorldStats`
- `relation_status*`: string，当前登录用户与该 world 的关系状态；可为 `anonymous` / `owner` / `joined` / `pending` / `approved` / `rejected`
- `characters*`: `Character[]`
- `locations*`: `Location[]`

### GET `/api/v1/world/map`

读取 world 的 2.5D 地图。匿名可访问并沿用 world 公开可见性规则。`definition_version != 2` 时成功返回空对象 `data={}`。

Query：

- `world_id*`: string
- `location_id*`: string；`root` 返回 world 主地图，其他值返回对应 location 地图

响应 `data`：

- 2.5D 地图：

  ```json
  {
    "tile_types": {
      "L3_classroom__modern_v4": "https://cdn-001.worldo.ai/predata/tiles/tile_d_1/L1/tiles/L3_classroom__modern_v4.png"
    },
    "map_json": {
      "width": 5,
      "height": 5,
      "tiles": [
        {
          "x": 0,
          "y": 0,
          "type": "L3_classroom__modern_v4",
          "shadow": 1,
          "location_id": "loc_1"
        }
      ]
    }
  }
  ```

  - `tile_types`: `object|null`，key 为瓦片类型，value 为该类型对应的线上图片 URL
  - `map_json`: `object|null`
  - `map_json.width`: integer，地图横向瓦片总数
  - `map_json.height`: integer，地图纵向瓦片总数
  - `map_json.tiles`: `MapTile[]`，地图中的瓦片列表
  - `MapTile.x`: integer，瓦片横坐标
  - `MapTile.y`: integer，瓦片纵坐标
  - `MapTile.type`: string，对应 `tile_types` 中的 key
  - `MapTile.shadow`: integer，`0` 表示保持原始亮度并参与组成明亮地块边界，`1` 表示处于边界外的迷雾图层区域；迷雾覆盖整个可见网格，从边界透明开始，随距离增加逐渐变暗，远端达到纯黑
  - `MapTile.location_id`: string，可选；瓦片关联的 location ID
- 旧版地图：`{}`

错误码：

- `1404`：world 不存在、不可见，或指定 location 不存在
- `4004`：缺少 `world_id` 或 `location_id`

### GET `/api/v1/world/origin_progress`

根据 `uid + origin_id` 查询该用户创建或加入过的 active world 成员关系，返回 `current_tick_no` 最大的一条 world 及 tick 数。无匹配时返回 `world_id=""`、`tick_cnt=0`。

Query：

- `uid*`: string，用户 uid
- `origin_id*`: string，origin 业务 id

响应 `data`：

- `world_id*`: string
- `tick_cnt*`: integer

错误码：

- `4004`

### POST `/api/v1/world/apply`

玩家发起加入 world 的申请；同一 `(world_id, applicant_uid)` 不能存在 pending/approved 的活跃申请。

请求 body：

- `world_id*`: string
- `message`: string

响应 `data`：

- `apply_id*`: string
- `status*`: integer，`10` 表示 pending

错误码：

- `20101`：`origin_id` 不存在或已软删除
- `20201`
- `20203`
- `20204`
- `20205`

### GET `/api/v1/world/apply/list`

查询 world 加入申请列表。`world_id` 为空时表示申请人视角，仅列出当前登录用户发起过的申请；传入 `world_id` 时用于 owner 审批列表。

Query：

- `pn`: integer
- `rn`: integer
- `world_id`: string
- `status`: integer

响应 `data`：

- `total*`: integer
- `pn*`: integer
- `rn*`: integer
- `list*`: `WorldApply[]`

`WorldApply`：

- `apply_id*`: string
- `world_id*`: string
- `applicant_uid*`: string
- `message`: string
- `status*`: integer
- `reviewer_uid`: string
- `review_msg`: string
- `reviewed_at`: integer
- `joined_at`: integer
- `created_at`: integer

错误码：

- `10001`
- `10003`
- `20201`

### POST `/api/v1/world/apply/review`

world owner 审批一条 pending 申请。`action=approve` 流转到 approved；`action=reject` 流转到 rejected（终态）。被拒绝的申请允许同一申请人重新发起新的 apply。

请求 body：

- `apply_id*`: string
- `action*`: string，`approve` 或 `reject`
- `review_msg`: string

响应 `data`：

- `apply_id*`: string
- `status*`: integer，`20` 表示 approved

错误码：

- `4004`
- `10001`
- `10003`
- `20202`
- `20206`

### POST `/api/v1/world/join`

申请通过后玩家正式加入 world。语义与 `origin/launch` 一致：`preset_character_id` 与 `custom_role` 二选一互斥。

请求 body：

- `world_id*`: string
- `preset_character_id`: string，必须命中该 world 中 `type=ai` 且 `player_uid` 为空的角色
- `custom_role`: `WorldCustomRole`

响应 `data`：

- `world_id*`: string
- `char_id*`: string

错误码：

- `4004`
- `10001`
- `10003`
- `20201`
- `20202`
- `20204`
- `20206`
- `20207`

### GET `/api/v1/world/tick/list`

按 `world_id` 分页读取 `tbl_world_tick` 中 `status=50 (p2_done)` 的 tick。列表按 `tick_no DESC, id DESC` 排序，最新已完成 tick 在前。

接口公开可访问。pending、approved world 对所有人可见；rejected world 仅 owner 可见，其他调用方返回 `ErrorWorldNotExist`。

Query：

- `world_id*`: string
- `pn`: integer，页码，从 1 开始
- `rn`: integer，每页条数，默认 10

Apifox 可选 Header：

- `x-debug-uid`: string
- `x-app-version`: string；正式 App 由共享 Gateway 请求链注入 `X-App-Version`，接口 resource 不单独拼装公共 Header

响应 `data`：

- `list*`: `Tick[]`
- `total*`: integer
- `pn*`: integer
- `rn*`: integer

错误码：

- `4004`
- `20201`

### POST `/api/v1/world/tick`

world owner 触发一次 tick。该接口替代旧的 progress 触发接口，不保留旧接口兼容；请求字段使用 `world_id`，不再使用 `wid`。

前置条件：

- 必须登录。
- 调用方必须等于 `world.owner_uid`，否则返回 `10011`。

服务端行为：

- 取当前 `max(tick_no) + 1` 作为新 `tick_no`。
- 写入 `tbl_ticks`，包括 `obj_type=2`、`obj_id=world_id`、`narrator`、`paragraphs`。
- 更新 `tbl_worlds.tick_cnt + 1`，刷新 `world_last_tick_time`，并将 `status` 置为 `20`（tick 中）。

请求 body：

- `world_id*`: string

响应 `data`：

- `world_id*`: string
- `tick_cnt*`: integer
- `last_tick*`: `Tick`

错误码：

- `4004`
- `10001`
- `10011`
- `20201`

### GET `/api/v1/origin/list`

返回 origin 模板列表。origin 是 world 的模板，可被复制为 world。列表项默认返回 `info + stats`。默认 `scene=popular`；`scene=uid` / `scene=mine` 按 `origin.updated_at DESC` 排序，其他场景按 `copy_cnt DESC` 排序，`scene=foryou` 取所有 origin。`scene=popular` 时，每个列表项额外返回 `discusses`，包含该 origin 最新 2 条已审核通过的顶级评论。匿名可访问；仅 `scene=mine` 需要登录。

Query：

- `pn`: integer，页码，从 1 开始
- `rn`: integer，每页条数，默认 10，最大 100
- `tag_id`: integer，按 tag 过滤
- `keyword`: string，模糊搜索 `origin_name` / `brief`
- `scene`: string，场景；默认 `popular`，可用值包括 `popular`、`foryou`、`uid`、`mine`、`tag`
- `uid`: string，`scene=uid` 时传入目标用户 uid；`scene=mine` 时不传
- `tag`: string，`scene=tag` 时传入标签名

响应 `data`：

- `total*`: integer
- `pn*`: integer
- `rn*`: integer
- `list*`: `{ info: OriginInfo, stats: OriginStats, discusses?: DiscussItem[] }[]`；`discusses` 仅 `scene=popular` 返回，最多 2 条顶级评论

每个 `list[].info` 额外明确包含：

- `definition_version*`: integer，地图定义版本；`1` 为旧版地图，`2` 为新版 2.5D 地图
- `default_map_location_id*`: string，默认展示地图的 location id；`root` 表示根地图

### GET `/api/v1/origin/feed`

按设备返回去重后的 Origin For you 推荐流。请求统一通过 Gateway 链路携带必填 `X-Device-ID`。`start_score` 是不包含自身的 Redis ZSET 位置游标；刷新传 `0`，分页传上一次响应的 `next_score`。

Query：

- `start_score`: int64，默认 `0`，最小值 `0`
- `rn`: integer，默认 `10`，范围 `1..100`

响应 `data`：

- `list*`: `{ info: OriginInfo, stats: OriginStats }[]`
- `rn*`: integer
- `next_score*`: int64，服务端本次最后检查的位置；被曝光记录过滤的成员仍会推进该游标
- `has_more*`: boolean，`next_score` 之后是否仍有成员

每个 `list[].info` 额外明确包含：

- `definition_version*`: integer，地图定义版本；`1` 为旧版地图，`2` 为新版 2.5D 地图
- `default_map_location_id*`: string，默认展示地图的 location id；可直接作为 `/api/v1/origin/map` 的 `location_id`，`root` 表示根地图

客户端检测到 `next_score` 未前进时必须停止继续分页，防止异常响应造成重复请求。

### POST `/api/v1/origin/feed/exposure`

上报当前设备实际看到的 Origin。请求统一通过 Gateway 链路携带必填 `X-Device-ID`；服务端对请求内 ID 和同设备重复请求幂等，并按上海自然日保存曝光集合。

JSON body：

- `origin_ids*`: string[]，数量 `1..100`

响应 `data`：

- `recorded_count*`: integer

客户端只统计封面图片已成功渲染、在列表真实内容视口内可见面积至少 30% 且连续可见满 1.5 秒的卡片；占位图、图片加载中或加载失败时不开始计时。可见面积低于 30% 时取消本次计时，重新进入后重新计时。快速经过的卡片不采集，当前页面生命周期内按 OID 去重。服务端 `5000` 或可重试网络错误最多尝试 3 次，参数错误 `4004` 不重试。

### GET `/api/v1/origin/hot_tags`

返回 origin 热门 tag。当前服务端固定返回 5 个 tag，后续可替换为 DB 聚合。匿名可访问，不需要登录。

请求参数：无。

响应 `data`：

- `list*`: string[]

### GET `/api/v1/origin/my_launch_preset_characters`

根据当前登录用户与 `origin_id`，返回该用户过去作为 world owner launch 该 origin 时选择过的 preset 角色。

custom 角色和后续通过 `world/join` 绑定的角色不返回。结果由服务端先按 `last_active_at` 倒序排列，再应用 `limit`。已软删除的 world 仍属于 launch 历史；但只返回当前 origin 中仍未软删除的角色，角色展示字段取当前 origin 的角色定义，不取历史 world 副本。

接口需要登录。origin 可见性与 `/api/v1/origin/detail` 一致：approved 对所有登录用户可见，pending/rejected 仅 origin owner 可见。

客户端通过共享 `GenesisApi` / `ApiClient` 请求链路发送，不声明接口私有 header；统一复用公共 runtime header、登录态 `Authorization` 以及配置的 Gateway `X-*` 签名 header。旧公共 `device-id/app-id/app-version/app-platform` header 仍按客户端全局规则过滤，不在本接口单独恢复。

Query：

- `origin_id*`: string，要查询 launch 历史的 origin 业务 id
- `limit*`: integer，返回数量；Opening Sheet 固定传 `5`

服务端先按 `last_active_at DESC` 排序，再应用 `limit`，因此
`limit=5` 返回最近活跃的 5 个 World；客户端直接按响应顺序展示。

响应 `data`：

- `list*`: `OriginMyLaunchPresetCharacter[]`；没有匹配历史时返回空数组

`OriginMyLaunchPresetCharacter`：

- `char_id*`: string，当前 origin 中的 preset 角色 id，也是去重键
- `type*`: string，固定为 `ai`
- `name*`: string
- `identity*`: string
- `brief*`: string，当前 origin 角色的 personality
- `goal*`: string
- `avatar*`: `ImageResource`
- `initial_location_id*`: string，当前 origin 角色的初始地点 id
- `last_launched_at*`: integer，最近一次使用该角色 launch 的 Unix 秒
- `world_id*`: string，最近一次使用该角色 launch 的 World 业务 id
- `tick_no*`: integer，该 World 当前 Tick 数
- `sub_tick_no*`: integer，该 World 当前子 Tick 数
- `connect_cnt*`: integer，该 World 当前累计 Message 数
- `current_time*`: string，该 World 当前时间
- `last_active_at*`: integer，该 World 最近活跃时间，Unix 秒

错误码：

- `4004`：缺少 `origin_id`，或 `limit` 非法
- `10001`：未登录或 session 过期
- `20101`：origin 不存在、已软删除或当前调用方不可见

### GET `/api/v1/app/config`

App 启动时尽早请求的全局配置。客户端在首个 Flutter 页面展示前完成一次有超时兜底的加载；失败或超时使用默认值。

Query：

- `uid`: string，可选；客户端完成本地登录 UID 读取后传入真实非 guest UID，未登录、读取失败或读取超时时不传。该字段用于用户维度的配置判断，不替代 `Authorization` 身份校验。

响应 `data`：

- `show_opening_sheet`: boolean；决定进入 Origin Detail 时 Opening Sheet 的首帧状态。`true` 时首次构建即完全展开，`false` 时首次构建即保持收起；不等待 `/api/v1/origin/detail` 返回后再改变 Sheet 高度。
- `apiTraceSamplingRate`: float，范围 `[0,1]`；普通业务接口请求监控的启动级采样率。客户端本地默认值为 `0`，服务端当前返回 `1`。配置接口以及 `/apix/v1/time`、`/apix/v1/app/device/challenge`、`/apix/v1/app/device/register` 固定独立监控；轮询接口和 `/api/v1/collect` 不参与接口请求监控。

```json
{
  "err_no": 0,
  "err_msg": "succ",
  "data": {
    "show_opening_sheet": false,
    "apiTraceSamplingRate": 1.0
  }
}
```

### GET `/api/v1/origin/detail`

返回单个 origin 模板的完整详情：基本信息、统计信息、初始地点对白、初始角色、初始 location、模板 ticks。`info` 返回 `definition_version`，不返回 `tile_types`；location 不返回 `location_description`；主地图及 location 均不返回 `map_json`，需要时调用 `/api/v1/origin/map`。

匿名可访问。已审核通过（`review_status=20`）的 origin 对所有人可见；pending/rejected 仅 owner 可见，其他调用方统一收到 `ErrorOriginNotExist`。

Query：

- `origin_id*`: string

Apifox 可选 Header：

- `x-debug-uid`: string
- `x-app-version`: string；正式 App 由共享 Gateway 请求链注入 `X-App-Version`

响应 `data`：

- `info*`: `OriginDetailInfo`
- `stats*`: `OriginStats`
- `init_location_group*`: `OriginInitLocationGroup|null`
- `characters*`: `OriginDetailCharacter[]`
- `locations*`: `Location[]`，本接口不包含 `location_description`
- `ticks*`: `Tick[]`

`OriginInitLocationGroup`：

- `location_id*`: string
- `initial_dialogue*`: `OriginInitialDialogueLine[]`
- 服务端优先返回 `edit_data` 配置的可用目标；目标不可用时，按 `location_id` 升序选择第一条具有有效非空 `dialogue` 的 location；均不存在时返回 `null`

`OriginInitialDialogueLine`：

- `char_id*`: string，角色 id 或 `nar`、`nar_pic`、兼容旧值 `image`
- `char_name*`: string，只读；`nar/nar_pic` 为 `Narrator`，角色 id 使用最终角色名
- `content*`: string，对白、旁白或图片 URL

`Character`：

- `char_id/type/player_uid/player_username/player_user/player_joined_at*`
- `name/identity/brief/goal/avatar*`
- `initial_location_id/location_id/metric_value/delta*`
- `is_recommend*`: integer，`0` 不推荐、`1` 推荐
- origin 模板中的角色 `type=ai`、`player_uid=""`、`player_joined_at=0`；`initial_location_id` 与运行态 `location_id` 是两个独立字段

`Location`：

- `location_id/level/location_pid/location_name*`
- `location_paragraph/location_timestamp/location_summary*`；不返回 `location_description`
- `image/x_percent/y_percent/x/y/map_url/dialogue*`
- `x/y` 是 2.5D 地图坐标，旧版地图为 `0`；`dialogue` 行为 `{char_id,char_name,content}`

`Tick`：

- `tick_id/tick_no/sub_tick_no/status/created_at*`
- `tick_result*`: `{current_time,narrator,paragraphs}`，不返回 `location_groups`
- `paragraphs[]*`: `{location_id,timestamp,text,visibility,visible_to,clue,character_deltas}`；`visibility` 为 `public` 或 `char_only`，P1 v2 的 `character_deltas` 为空数组

错误码：

- `4004`：缺少 `origin_id`
- `20101`：origin 不存在、已软删除或当前调用方不可见

### GET `/api/v1/origin/map`

读取 origin 模板的 2.5D 地图。匿名可访问并沿用 origin 公开可见性规则。`definition_version != 2` 时成功返回空对象 `data={}`。

Query：

- `origin_id*`: string
- `location_id*`: string；`root` 返回 origin 主地图，其他值返回对应 location 地图

响应 `data`：

- 2.5D 地图：

  ```json
  {
    "tile_types": {
      "L3_classroom__modern_v4": "https://cdn-001.worldo.ai/predata/tiles/tile_d_1/L1/tiles/L3_classroom__modern_v4.png"
    },
    "map_json": {
      "width": 5,
      "height": 5,
      "tiles": [
        {
          "x": 0,
          "y": 0,
          "type": "L3_classroom__modern_v4",
          "shadow": 1,
          "location_id": "loc_1"
        }
      ]
    }
  }
  ```

  - `tile_types`: `object|null`，key 为瓦片类型，value 为该类型对应的线上图片 URL
  - `map_json`: `object|null`
  - `map_json.width`: integer，地图横向瓦片总数
  - `map_json.height`: integer，地图纵向瓦片总数
  - `map_json.tiles`: `MapTile[]`，地图中的瓦片列表
  - `MapTile.x`: integer，瓦片横坐标
  - `MapTile.y`: integer，瓦片纵坐标
  - `MapTile.type`: string，对应 `tile_types` 中的 key
  - `MapTile.shadow`: integer，`0` 表示保持原始亮度并参与组成明亮地块边界，`1` 表示处于边界外的迷雾图层区域；迷雾覆盖整个可见网格，从边界透明开始，随距离增加逐渐变暗，远端达到纯黑
  - `MapTile.location_id`: string，可选；瓦片关联的 location ID
- 旧版地图：`{}`

错误码：

- `1404`：origin 不存在、不可见，或指定 location 不存在
- `4004`：缺少 `origin_id` 或 `location_id`

### GET `/api/v2/origin/foredit`

登录用户读取自己创建的 Origin 完整详情，用于 V2 地图编辑。服务端先校验 `tbl_origin.owner_uid` 等于当前登录 uid，再返回与 `GET /api/v1/origin/detail` 完全相同的 `OriginDetail`。

本接口不再返回 V1 foredit 的平级 `edit_data` 形态；客户端必须从嵌套的 `data.info` 读取基本信息，并从顶层 `init_location_group`、`characters`、`locations`、`ticks` 读取对应编辑数据。

Query：

- `origin_id*`: string

响应 `data`（`OriginDetail`）：

- `info*`: `OriginDetailInfo`
- `stats*`: `OriginStats`
- `init_location_group*`: `OriginInitLocationGroup`
- `characters*`: `Character[]`
- `locations*`: `Location[]`
- `ticks*`: `Tick[]`

字段定义与上方 `GET /api/v1/origin/detail` 相同，其中 `characters[].is_recommend` 为 integer：`0` 不推荐、`1` 推荐。`info` 包含 `origin_id/origin_name/origin_version/origin_version_time/definition_version/language/current_time/owner_uid/owner_name/owner_user/brief/tags/metric/created_at/cover/map_url/status`。特别注意：新契约没有旧平级 foredit 的 `setting/events/started_at/tick_duration_time/tile_types` 字段。

错误码：

- `4004`: ErrorParamInvalid，缺少 `origin_id`
- `10001`: ErrorUserNotLogin
- `10011`: ErrorUserNotAccess，当前用户不是该 origin 的 owner
- `20101`: ErrorOriginNotExist，`origin_id` 不存在或已软删除

### POST `/api/v1/origin/create`

登录用户基于 info、characters 和平级 locations 创建新的 origin 模板。同步阶段写入主表并立即返回轻量 `OriginUpsertResp`；`owner_uid` 取自 session，不接受请求体覆盖，初始 `origin_version=1`、`review_status=10`、`status=20 processing`。

服务端行为：

- characters/locations 中重复的 `char_id` / `location_id` 按首次出现保留。
- `language` 来自 `x-system-language` header；`current_time` 优先使用 trim 后的 `started_at`，空值写 `Day 1`。
- 后台调用 `origin_init_tags_locations` 补全 tags 和三级 location 树；成功后批量写角色/location、回填计数，并切回 `status=10 normal`。
- prompt 失败或没有可用地点时，若请求 locations 非空，会用请求地点名构造最小三级树。
- V2 编辑回显通过 `/api/v2/origin/foredit` 读取当前完整 `OriginDetail`，不消费旧平级 `edit_data` 响应。
- `ticks` 不在 create 范围内。

请求 body（`OriginCreateReq`）：

- `origin_name*`: string
- `origin_version`: string，create 时服务端默认写 `1`
- `definition_version`: integer，`1` 或 `2`；V1 未传时写 `1`
- `brief`: string
- `setting`: string
- `events`: string[]
- `tags`: string[]
- `metric`: `WorldMetric`
- `started_at`: string，故事内起始时间文本
- `tick_duration_time`: string，每个 tick 推进的故事时间跨度文本；为空时服务端写默认 `1 day`
- `cover`: string 或 `ImageResource`
- `map_url`: string
- `tile_types`: object 或 null
- `characters`: `OriginCharacterUpsert[]`
- `locations`: `OriginLocationUpsert[]`

`OriginCharacterUpsert`：

- `char_id`: string，请求内临时引用 id；服务端按数组顺序重写
- `name*`: string
- `identity`: string
- `personality`: string，详情接口中以 `character.brief` 返回
- `bio`: string，详情接口中以 `character.description` 返回
- `goal`: string
- `avatar`: string 或 `ImageResource`
- `initial_location_id`: string，角色初始地点 id；`location_id` / `metric_value` 属于 tick 运行态，不在 create 入参中提供

`OriginLocationUpsert`：

- `location_id`: string，最长 32 字符，请求内临时引用 id；客户端新建节点使用 32 位、无连字符的小写 UUID v4，编辑已有节点时保留服务端原 ID
- `level`: integer，兼容字段；create/update 时服务端忽略
- `location_pid`: string，兼容字段；当前客户端会按表单树发送该关联，V2 foredit 通过完整 `Location` 返回服务端当前层级关系
- `location_name*`: string
- `location_description`: string，固定描述，tick 不会修改
- `location_summary`: string，兼容旧请求；当 `location_description` 为空时用于回填固定描述
- `image`: string 或 `ImageResource`
- `x_percent`: integer，`0-100`
- `y_percent`: integer，`0-100`
- `map_url`: string

响应 `data`：

- `origin_id*`: string
- `origin_version*`: string
- `origin_version_time*`: integer，Unix 秒
- `origin_name*`: string

错误码：

- `4004`
- `10001`

### POST `/api/v1/origin/update`

登录用户更新自己创建的 origin 模板。同步阶段校验 owner、更新主表、自动递增数字版本、清理当前主态 active ticks、写入 `status=20 processing`，随后立即返回轻量 `OriginUpsertResp`。

服务端行为：

- 后台使用 `origin_init_tags_locations` 补全 tags 和三级 location 树；旧异步任务通过 `origin_id + origin_version` 检查自动跳过。
- `locations` 作为用户平级编辑 location 入参；服务端忽略 `level` / `location_pid` 并重新生成入库三级树，成功后切回 `status=10 normal`。
- `characters` 只 upsert 请求列表中的项，不按缺失项推断删除；已有 `char_id` 保留，新增角色临时 id 会重写为下一个 `char_N`。
- `deleted_char_ids` / `deleted_location_ids` 显式软删；与本次提交项冲突时以提交项为准。
- `update_notes` 写入 `tbl_origin.update_notes`，后续生成版本快照时同步到 `tbl_origin_version.change_log`；客户端 publish 时要求用户填写。
- V2 编辑回显通过 `/api/v2/origin/foredit` 读取当前完整 `OriginDetail`，不消费旧平级 `edit_data` 响应。
- 不重置审核状态。

请求 body（`OriginUpdateReq`）：

- `origin_id*`: string
- `origin_name*`: string
- `origin_version`: string，服务端控制；每次更新成功自动进入下一数字版本
- `definition_version`: integer，`1` 或 `2`；V1 未传时保留当前值
- `brief`: string
- `setting`: string
- `events`: string[]
- `tags`: string[]
- `metric`: `WorldMetric`
- `started_at`: string，故事内起始时间文本
- `tick_duration_time`: string，每个 tick 推进的故事时间跨度文本，例如 `1 day`
- `cover`: string 或 `ImageResource`
- `map_url`: string
- `tile_types`: object 或 null
- `characters`: `OriginCharacterUpsert[]`
- `locations`: `OriginLocationUpsert[]`
- `update_notes`: string，版本更新说明；客户端 publish 时必填
- `deleted_char_ids`: string[]，显式删除的角色 id
- `deleted_location_ids`: string[]，显式删除的 location id

响应 `data`：

- `origin_id*`: string
- `origin_version*`: string
- `origin_version_time*`: integer，Unix 秒
- `origin_name*`: string

错误码：

- `4004`
- `10001`
- `10011`
- `20101`

### POST `/api/v2/origin/create`

使用自动地图流程创建 Origin。请求复用 `OriginCreateReq`（包括 `characters[].is_recommend`）并增加可选 `init_location_group`；服务端忽略客户端的 `definition_version` / `tile_types`，固定写入 `definition_version=2`、`status=20 processing`，同步返回与 V1 相同的轻量 `OriginUpsertResp`。

后台并发调用 `origin_init_tags` 与 `origin_create_map`，生成完整三级 location 树、root/location `map_json` 和实际使用的 CDN WebP `tile_types`。完整地图原子落库后切回 `status=10 normal`；失败时保持 processing，不发布半成品。

额外请求字段：

- `characters[].is_recommend`: integer，`0` 不推荐、`1` 推荐；同一个 Origin 最多一个角色为 `1`
- `init_location_group`: object，可选
  - `location_id*`: string，必须命中最终生成的 location
  - `initial_dialogue*`: `{char_id, content}[]`
  - `char_id` 可为角色 id，也可为 `nar`、`nar_pic` 等展示消息类型

错误码：`4004`、`10001`。

### POST `/api/v2/origin/update`

更新 owned Origin 并重新生成完整 2.5D 地图。请求复用 `OriginUpdateReq`（包括 `characters[].is_recommend`）并增加可选 `init_location_group`；服务端固定 `definition_version=2`，同步复用 owner 校验、版本递增、active tick 清理和 `deleted_*` 处理，返回轻量 `OriginUpsertResp`。

生成期间保留上一版 `map_json` / `tile_types`，成功后原子替换；旧异步任务按 `origin_version` 自动跳过。省略 `init_location_group` 表示清空旧初始对白，传入时完整替换；其 `location_id` 与 `deleted_location_ids` 冲突会同步返回参数错误。

错误码：`4004`、`10001`、`10011`、`20101`。

### POST `/api/v1/origin/launch`

登录用户基于一个 origin 模板创建新的 world 实例；接口只创建 world，不触发 tick。

请求 body（`OriginLaunchReq`）：

- `origin_id*`: string，待 launch 的 origin 业务 id
- `preset_character_id`: string，origin 角色列表中的 `char_id`
- `preset_character_override`: object，可选；服务端支持 `name/identity/personality/bio/goal/avatar`，用于覆盖新 world 中绑定原 `char_id` 的角色副本
- `custom_role`: `WorldCustomRole`

`preset_character_id` 与 `custom_role` 必须二选一；两者都为空或都非空会返回 `4004`。
`preset_character_override` 只能用于 preset 模式，并且至少包含一个允许覆盖的字段；custom 模式携带时服务端忽略。

`WorldCustomRole`：

- `char_id`: string，可空；为空时服务端按 `char_<uid>` 兜底
- `name*`: string
- `identity`: string
- `personality`: string，角色 Personality
- `bio`: string
- `goal`: string
- `avatar`: string
- `initial_location_id`: string，玩家进入 world 时的初始地点；服务端同时作为当前 `location_id` 写入

响应 `data`：

- `world_id*`: string

错误码：

- `4004`
- `10001`
- `20101`
- `20102`

## Chatroom HTTP 接口

这些接口不在 `/api/v1` 下，而在 chatroom 服务前缀 `/aitown-chat` 下。当前 Flutter 侧通过 `GenesisApi.chatroomHttp` 使用独立 base URL，默认 `GENESIS_CHATROOM_HTTP_URL=https://api.worldo.ai/`；本地 mock 已覆盖这些路由。

### GET `/aitown-chat/api/ulocation`

获取指定世界内所有角色（AI + 真实用户）的位置信息，按地点分组返回。

数据来源：

- 所有角色从 `world.detail` 接口的 `characters` 字段获取
- 真实用户：`player_uid` 不为空，`location_id` 从在线 session 获取
- AI 角色：`player_uid` 为空，`location_id` 从 `world.detail` 获取

使用场景：

- 客户端收到 `world_change` 消息后，调用此接口刷新世界状态
- 客户端收到 `user_location_change` 消息后，调用此接口获取最新位置

Query：

- `world_id*`: string，世界实例 ID

响应 `data`：

- `world_id`: string，世界实例 ID
- `locations`: `{ location_id, characters: ChatroomLocationCharacter[] }[]`

`ChatroomLocationCharacter`：

- `char_id`: string，角色 ID
- `player_uid`: string，真实用户 UID；AI 角色为空字符串
- `player_username`: string，真实用户名；AI 角色为空字符串
- `name`: string，角色名称
- `location_id`: string，当前地点 ID

错误响应示例：

```json
{ "err_no": 400, "err_msg": "world_id 不能为空" }
```

### GET `/aitown-chat/internal/world/messages`

获取指定世界最近 50 条消息，并按 `location_id` 分组返回。

该接口保留给旧协议的 world 级恢复/诊断链路；location chat 页的 initial、older 和 gap 请求不直接依赖它，V2 地点历史统一走下述 per-location 接口。

Query：

- `world_id*`: string，世界实例 ID

响应 `data`：

- `locations`: `{ location_id, messages: ChatroomMessageDTO[] }[]`

错误响应示例：

```json
{ "err_no": 1001, "err_msg": "参数错误: world_id is required" }
```

### GET `/aitown-chat/api/messages`

旧协议兼容/诊断接口。获取指定世界、指定地点的扁平历史消息；新 location chat 运行时不再以它作为 initial、older 或 gap 数据源。`limit` 默认 20，最大 100。

Query：

- `world_id*`: string，世界实例 ID
- `location_id*`: string，地点 ID
- `since`: integer，起始消息 ID；`0` 表示获取最新
- `limit`: integer，默认 `20`，最大 `100`

响应 `data`：

- `messages`: `ChatroomMessageDTO[]`
- `has_more`: boolean，是否有更多消息
- `newest_message_id`: integer，最新消息 ID

`data` 为上述扁平对象，单地点接口不返回 world 级接口使用的 `locations[]` 包装。`messages[]` 可同时包含普通 location 消息及三类时间线记录；时间线记录的 `location_message_id` 既可能为正数，也可能为 `0`。

图片消息仅在单条 `ChatroomMessageDTO` 中新增 `message_type`，不改变现有响应 envelope、消息 ID 字段或时间字段。例如：

```json
{
  "global_message_id": 90003,
  "message_id": 1003,
  "location_message_id": 103,
  "location_id": "loc_001",
  "conversation_round_id": 7003,
  "sender_type": "narrator",
  "sender_id": "nar_pic",
  "sender_name": "Narrator",
  "user_id": "",
  "content": "https://example.com/images/scene.jpg",
  "message_type": "image",
  "current_time": "Day 1, 08:05",
  "tick_no": 3,
  "created_at": "2026-07-27 10:05:00"
}
```

### GET `/aitown-chat/api/v2/messages`

获取指定世界、指定地点的 V2 历史消息。HTTP V2 不读取 `x-app-version`，始终返回完整 V2 DTO；`limit` 默认 20，最大 100。

Query：

- `world_id*`: string，世界实例 ID
- `location_id*`: string，地点 ID
- `since`: integer，严格使用 `location_message_id` 的向前分页游标；`0` 表示获取最新页
- `limit`: integer，默认 `20`，最大 `100`

响应 `data`：

- `messages`: `ChatroomV2MessageDTO[]`，按 `location_message_id` 倒序
- `has_more`: boolean，是否还有更早的地点消息
- `newest_message_id`: integer，当前请求地点最新的 `location_message_id`，不受 `since` 当前页影响

下一页 `since` 必须使用本页最后一条消息的 `location_message_id`，不得改用 world `message_id`。示例：

```json
{
  "err_no": 0,
  "err_msg": "succ",
  "data": {
    "messages": [
      {
        "type": "tick",
        "stream_type": "",
        "ts": 1786340797000,
        "world_id": "world_001",
        "location_id": "loc_2_2_2",
        "global_message_id": 8702,
        "message_id": 101,
        "location_message_id": 29,
        "conversation_round_id": 7359,
        "sender_type": "tick",
        "sender_id": "tick",
        "sender_name": "SubTick",
        "message_type": "text",
        "min_app_version": 0,
        "created_at": "2026-08-10 11:06:37",
        "payload": {
          "current_time": "Day 1, 13:50",
          "tick_no": 1,
          "sub_tick_no": 2,
          "global": "The promise-shaped key pulses.",
          "story_events": [],
          "characters_moved": []
        },
        "err_no": 0,
        "err_msg": ""
      }
    ],
    "has_more": false,
    "newest_message_id": 29
  }
}
```

### POST `/aitown-chat/internal/tick/lock`

Tick 服务锁定 world，chat 服务按 WebSocket 新协议广播 `tick_start`，阻止用户继续发送消息。

Query / multipart form：

- `world_id*`: string，世界实例 ID；Apifox 同时声明 query 与 `multipart/form-data` body

响应 `data`：

- `locked`: boolean

### GET `/aitown-chat/internal/tick/progress`

Tick 服务轮询 world 处理进度。

Query：

- `world_id*`: string，世界实例 ID

响应 `data`：

- `progress`: integer，`1` 表示完成，`0` 表示进行中
- `pending_messages`: integer，待消费消息数
- `active_llm_calls`: integer，活跃 LLM 调用数

### POST `/aitown-chat/internal/tick/unlock`

Tick 服务解锁 world，chat 服务按 WebSocket 新协议广播 `tick_done`，用户可以继续发送消息。

multipart form：

- `world_id`: string，世界实例 ID

响应 `data`：

- `unlocked`: boolean

### POST `/aitown-chat/internal/narrator/write`

旁白服务写入旁白消息，并按 WebSocket 新协议广播 `nar_new_message` 给对应 location 用户。

JSON body：

- `world_id*`: string
- `tick_id*`: string
- `location_groups*`: `ChatroomNarratorLocationGroup[]`

本次图片消息增量只更新 `nar_new_message` 下行事件和历史消息返回 DTO；没有修改该接口的请求结构。

响应 `data`：

- `message_id`: integer，写入消息 ID

## Search 接口

### GET `/api/v2/search`

Meilisearch 全局搜索。请求参数和响应 envelope 沿用 v1；`type` 为空字符串时表示同时搜索 origin、world、user 三类。

相较 `/api/v1/search`：

- 在线请求完全使用 Meilisearch，不再回查 MySQL。
- Origin 搜索范围包含名称、brief、人物姓名和 Tag；World 搜索名称和 Tag；User 搜索姓名。Tag 优先级最低，支持完整词、词项和前缀命中，但不允许 typo。
- `keyword` trim 后少于 3 个 Unicode 字符仍返回空结果。
- 当 `keyword` 以小写 `o_`、`w_`、`u_` 开头且 Unicode 长度恰好为 8 时，只在对应索引做 ID 精确匹配；其他长度按普通文本搜索。
- ID 精确匹配时，显式 `type` 与 ID 前缀不一致会返回成功 envelope 和三类空结果；不支持的 `type` 也按相同方式返回空结果。
- `keyword/type/pn/rn`、`x-system-language`、`SearchEnvelope` 以及 `origins/worlds/users` 三段响应结构保持不变。

Query：

- `keyword`: string
- `type`: string，空字符串表示三类都搜；可传 `origin`、`world`、`user`
- `pn`: integer，页码，从 1 开始
- `rn`: integer，每页条数

响应是 `SearchV2Envelope`，HTTP 状态始终为 200，通过 `err_no` 区分结果：

- 成功 `SearchV2SuccessEnvelope`：`err_no*=0`、`err_msg*`、`data*: SearchV2Resp`
- 失败 `SearchV2ErrorEnvelope`：`err_no*!=0`、`err_msg*`、`data*={}`；`data` 不允许额外字段

`SearchV2Resp`：

- `keyword*`: string，回显搜索词
- `type*`: string，回显搜索类型；空字符串表示三类各以 `pn=1/rn=3` 返回预览
- `origins*`: `SearchV2OriginResult`
- `worlds*`: `SearchV2WorldResult`
- `users*`: `SearchV2UserResult`

三个 Result 都完整保留 `list/total/pn/rn`：`total` 是 int64、最大 20；`pn` 最小 1；`rn` 最小 1、最大 20。`type` 为空时忽略请求 `pn/rn` 并分别返回三类最多 3 条；显式指定类型时只有选中类型返回 list，但三类都返回实际 total。`list` 的 item 类型分别为 `SearchV2OriginItem`、`SearchV2WorldItem`、`SearchV2UserItem`。

`SearchV2OriginItem`（全部必填）：

- `origin_id/origin_name/origin_version/brief/language`: string；`origin_version` 与 `origin_name` 同级
- `cover`: `ImageResource`
- `tags`: string[]
- `characters`: `SearchV2OriginCharacter[]`
- `owner`: `SearchV2Owner`
- `stats`: `SearchV2OriginStats`
- `matches`: `SearchV2Match[]`，包含名称、brief、最多 5 个人物及所有 Tag 命中
- `matches_truncated`: boolean；只表示人物姓名命中超过 5 项被截断，不表示 `origin_name` 或 `brief` 被截断

`SearchV2WorldItem`（全部必填）：

- `world_id/world_name/origin_id/language`: string
- `cover`: `ImageResource`
- `tags`: string[]
- `owner`: `SearchV2Owner`
- `stats`: `SearchV2WorldStats`
- `created_at`: int64
- `matches`: `SearchV2WorldMatch[]`，包含 World 名称及所有 Tag 命中

`SearchV2UserItem`（全部必填）：

- `uid/name`: string
- `avatar`: `ImageResource`
- `matches`: `SearchV2UserNameMatch[]`，最多 1 项

共享子模型：

- `ImageResource`: `sm_url* / xl_url* / object_key*`，均为 string
- `SearchV2Owner`: `uid* / name* / avatar*`；契约中没有 `deleted`
- `SearchV2OriginCharacter`: `character_id* / name*`
- `SearchV2OriginStats`: `copy_cnt* / discuss_cnt* / character_cnt* / connect_cnt* / location_cnt* / max_tick_cnt*`，均为 integer
- `SearchV2WorldStats`: `tick_cnt* / sub_tick_no* / connect_cnt* / character_cnt* / player_cnt*`，均为 integer；依次表示当前主线 Tick 序号、当前子 Tick 序号、累计 Connect 数、当前 Character 数和当前 Player 数
- `SearchV2TagMatch`: `field*=tag`、`tag_index*`、`highlight_ranges*`；`tag_index` 定位当前 item 的完整 `tags[]` 元素
- `SearchV2HighlightRange`: `start*` 最小 0，`length*` 最小 1；二者均以 UTF-16 code unit 为单位，例如 `A😀B` 中 `B` 的 `start=3`

Origin 的 `SearchV2Match` 是严格的 `oneOf`：

- `SearchV2TextMatch`: `field*=origin_name | brief`、`highlight_ranges*`，没有 `character_id`
- `SearchV2CharacterMatch`: `field*=character_name`、`character_id*`、`highlight_ranges*`
- `SearchV2TagMatch`: `field*=tag`、`tag_index*`、`highlight_ranges*`
- 每个 `highlight_ranges` 至少 1 项并按 `start` 升序；`origin_name`、`brief` 和 `character_name` 的范围分别作用于完整 `origin_name`、完整 `brief`、`character_id` 对应人物的完整 `name`
- Origin 最多返回 1 个 `origin_name`、5 个 `character_name`、1 个 `brief`，同时返回所有 Tag 命中；`matches_truncated` 只表示人物姓名被截断

World 与 User 使用独立命中模型，二者都没有 `character_id`：

- `SearchV2WorldNameMatch`: `field*=world_name`，范围作用于完整 `world_name`
- `SearchV2WorldMatch`: `SearchV2WorldNameMatch | SearchV2TagMatch`
- `SearchV2UserNameMatch`: `field*=user_name`，范围作用于 User item 的完整 `name`
- 所有模型都有必填 `highlight_ranges`，至少 1 项并按 `start` 升序

所有 match 都不返回原文或 HTML。客户端保留目标原始字符串和 UTF-16 范围，后续自行渲染高亮。

实现状态：保留 `SearchV1Api.search({query, type, pn, rn})` 调用入口，请求实际发送到 `/api/v2/search`。公共 envelope 仍由 `handleV1ResponseErrNo` 统一消费：成功时把 `data` 解析为 typed `SearchV2Response`（对应文档的 `SearchV2Resp`），失败时抛出带 `err_no/err_msg` 的业务异常。页面展示模型同时持有三类原始 typed item，不丢弃 `matches`。

## Discuss 接口

Apifox 当前定义的 discuss 业务类型只覆盖 origin：`biz_type=1`。列表和回复分页接口无需登录；其余写操作需要登录态，Apifox 安全定义为 cookie `AIUSS`。

### GET `/api/v1/discuss/list`

顶级评论分页列表，返回每条顶级评论下最新 3 条回复。无需登录可访问；登录态下会回填 `is_liked`。

服务端行为：

- 校验 `biz_type` 受支持，并校验 `biz_id` 对应业务实体存在。
- 顶级评论按 `(biz_type, biz_id, level=1, deleted_at IS NULL)` 过滤，按 `created_at DESC, id DESC` 分页。
- `top_total` 表示顶级评论数量；`total_all` 表示顶级评论加回复的全部未删数量。
- 每条顶级评论按 `root_discuss_id` 取最新 3 条未删回复。

Query：

- `biz_type*`: integer，当前 `1` 表示 origin
- `biz_id*`: string
- `pn`: integer，默认 1
- `rn`: integer，默认 10

响应 `data`：

- `list*`: `{ comment: DiscussItem, latest_replies: DiscussItem[] }[]`
- `top_total*`: integer，顶级评论数量
- `total_all*`: integer，顶级评论 + 回复全部未删数量
- `pn*`: integer
- `rn*`: integer

错误码：

- `4004`
- `20401`
- `20402`

### GET `/api/v1/discuss/replies`

顶级评论下的回复分页列表。无需登录可访问；登录态下会回填 `is_liked`。

服务端行为：

- 加载 `root_discuss_id` 对应的未删除 discuss 行。
- root 不存在返回 `ErrorDiscussNotExist`；root 不是 `level=1` 顶级评论返回 `ErrorDiscussRootNotTop`。
- 按 `(root_discuss_id, level=2, deleted_at IS NULL)` 过滤，按 `created_at DESC, id DESC` 分页。
- 批量加载作者用户信息与当前 viewer 的点赞集合，避免 N+1。

Query：

- `root_discuss_id*`: string
- `pn`: integer，默认 1
- `rn`: integer，默认 20

响应 `data`：

- `list*`: `DiscussItem[]`
- `total*`: integer，回复数量
- `pn*`: integer
- `rn*`: integer

错误码：

- `4004`
- `20403`
- `20404`

### POST `/api/v1/discuss/post`

发表一条顶级评论或回复。`root_discuss_id` 为空时发表顶级评论；非空时发表回复。

服务端行为：

- 校验 `biz_type` 受支持，且 `biz_id` 对应实体存在、未软删除。
- `content` 与 `images` 至少其一非空；`images` 最多 9 张，单条 URL 长度不超过 512。
- 顶级评论写入 `level=1`，并递增 `tbl_origins.discuss_cnt`。
- 回复写入 `level=2`，`root_discuss_id` 必须命中同业务下的顶级评论；`parent_discuss_id` 未传时默认等于 `root_discuss_id`，并递增 root 的 `reply_cnt`。

请求 body：

- `biz_type*`: integer，当前 `1` 表示 origin
- `biz_id*`: string
- `content`: string，与 `images` 至少其一非空
- `images`: string[]，最多 9 张
- `root_discuss_id`: string，顶级评论为空，回复时为所属顶级评论 id
- `parent_discuss_id`: string，回复直接目标；回复时可选

响应 `data`：

- `discuss_id*`: string
- `root_discuss_id*`: string，顶级评论为空字符串，回复时为所属顶级评论 id
- `level*`: integer

错误码：

- `4004`
- `10001`
- `20401`
- `20402`
- `20403`
- `20404`
- `20405`

### POST `/api/v1/discuss/delete`

登录用户软删除自己的评论或回复。仅作者本人可删；查询路径默认过滤 `deleted_at IS NULL`。

服务端行为：

- 删除顶级评论时递减 `tbl_origins.discuss_cnt`，下界为 0。
- 删除回复时递减 root 的 `reply_cnt`，下界为 0。
- 不级联删除回复或点赞明细。

请求 body：

- `discuss_id*`: string

响应 `data`：空对象。

错误码：

- `10001`
- `20403`
- `20406`

### POST `/api/v1/discuss/like`

登录用户对一条评论或回复点赞，接口幂等。服务端使用插入冲突忽略；仅当本次确实新插入点赞行时，`like_cnt += 1`。

请求 body：

- `discuss_id*`: string

响应 `data`：空对象。

错误码：

- `10001`
- `20403`

### POST `/api/v1/discuss/unlike`

登录用户取消点赞，接口幂等。从未点赞时直接返回成功；仅当本次实际删除点赞行时，`like_cnt -= 1`，下界为 0。

请求 body：

- `discuss_id*`: string

响应 `data`：空对象。

错误码：

- `10001`

## Direct Message 接口

这些接口替换旧的 `/api/v1/dm/*` 封装。最新 Apifox 以 peer 为客户端主键：客户端发送、拉取列表和标记已读时都传 `peer_uid` 或 `target_uid`，不再传 `conversation_id`、`message_id`、`last_read_seq`、`client_msg_id`。

### POST `/api/v1/direct_message/send`

当前登录用户向 `peer_uid` 发送一条私信。sender 不能是 peer；任一方拉黑对方会拒绝；互关用户可自由发送，未互关时受 ping-pong 限制；`content` 非空且长度不超过 1000 字符。

请求 body：

- `peer_uid*`: string
- `content*`: string

响应 `data`：

- `message*`: DirectMessage
- `conversation*`: DirectMessageConversation

错误码：`10001`、`10002`、`20301`、`20302`、`20303`、`20304`、`20305`。

实现状态：已封装在 `DmV1Api.send({peerUid, content})`。`chat_page.dart` 发送私信时先写入本地 DB 并以 `sending` 状态渲染；接口成功后用返回的 `message` 替换本地临时消息并 merge 返回的 `conversation`，接口失败则从本地 DB 删除该临时消息，但当前页面保留一条临时失败行并显示红色感叹号。

### GET `/api/v1/direct_message/conversations`

返回当前登录用户参与的 1 对 1 会话，按 `last_message_at` 倒序。无 `after_message_id` 时为全量分页模式，默认 `pn=1`、`rn=20`，最大 `rn=100`；有 `after_message_id` 时为增量同步模式，服务端返回该游标之后变更过的会话。

query：

- `pn`: integer，全量分页时使用
- `rn`: integer，全量分页时使用；客户端全量同步固定传 `100`
- `after_message_id`: string，客户端上次保存的 `next_after_message_id`；增量同步时只传该字段，不传 `pn/rn`

响应 `data`：

- `list*`: DirectMessageConversation[]
- `total*`: integer
- `pn*`: integer
- `rn*`: integer
- `next_after_message_id*`: string，下次增量同步要提交的游标

错误码：`10001`。

实现状态：已封装在 `DmV1Api.conversations({pn, rn, afterMessageId})`；传 `afterMessageId` 时客户端只发送 `after_message_id`。`DirectMessageConversationStore.syncConversations()` 会在无本地游标时循环请求 `pn=1/rn=100`、`pn=2/rn=100`，直到返回不足 100 条；有本地游标时只请求增量并按 `conv_id` merge 到本地 DB。`messages_page.dart` 订阅本地 store 渲染，不直接暴露全量分页细节。

### GET `/api/v1/direct_message/list`

分页返回当前登录用户与 `peer_uid` 之间的私信，按消息 id 倒序，最新在前；没有会话时返回空列表。默认 `pn=1`、`rn=20`，最大 `rn=100`。

query：

- `peer_uid*`: string
- `pn`: integer
- `rn`: integer

响应 `data`：

- `list*`: DirectMessage[]
- `total*`: integer
- `pn*`: integer
- `rn*`: integer

错误码：`10001`、`10002`。

实现状态：已封装在 `DmV1Api.list({peerUid, pn, rn})`。`chat_page.dart` 进入后先加载本地 DB，再请求 `pn=1/rn=20`；停留期间每 5 秒请求第一页并按 `msg_id` merge，滚动到顶部时按 `pn=2,3.../rn=20` 拉取本地没有的旧消息。DB 内消息状态为 `sending/sent`，发送失败消息不持久化，仅作为当前页面临时失败行展示。

### POST `/api/v1/direct_message/read`

将当前登录用户与 `peer_uid` 的会话未读数清零，并把 `last_read_message_id` 推到当前会话最新消息 id；会话不存在时幂等返回成功。

请求 body：

- `peer_uid*`: string

响应 `data`：空对象。

错误码：`10001`、`10002`。

实现状态：已封装在 `DmV1Api.markRead({peerUid})`。

### GET `/api/v1/direct_message/unread`

返回当前登录用户在所有会话中的未读消息总数。

响应 `data`：

- `unread_cnt*`: integer

错误码：`10001`。

实现状态：已封装在 `DmV1Api.unread`。

### POST `/api/v1/direct_message/block`

将 `target_uid` 拉黑，已拉黑时幂等成功；拉黑不会自动取消互相关注。

请求 body：

- `target_uid*`: string

响应 `data`：空对象。

错误码：`10001`、`10002`、`20301`。

实现状态：已封装在 `DmV1Api.block({targetUid})`。

### POST `/api/v1/direct_message/unblock`

取消对 `target_uid` 的拉黑，未拉黑时幂等成功。

请求 body：

- `target_uid*`: string

响应 `data`：空对象。

错误码：`10001`。

实现状态：已封装在 `DmV1Api.unblock({targetUid})`。

### GET `/api/v1/direct_message/blocks`

返回当前登录用户拉黑过的用户分页列表，按拉黑时间倒序。默认 `pn=1`、`rn=20`。

query：

- `pn`: integer
- `rn`: integer

响应 `data`：

- `list*`: UserInfo[]
- `total*`: integer
- `pn*`: integer
- `rn*`: integer

错误码：`10001`。

实现状态：已封装在 `DmV1Api.blocks`。

## Notify 接口

### GET `/api/v1/message/unread`

获取消息页未读统计。需登录态，Apifox 安全定义为 cookie `AIUSS`。

响应 `data`：

- `total_unread*`: integer
- `world_apply_unread*`: integer
- `follow_unread*`: integer
- `interaction_unread*`: integer
- `direct_message_unread*`: integer

实现状态：已封装在 `MessagesV1Api.unreadSummary()`。

### GET `/api/v1/message/notifications`

按消息块拉取非私信通知列表。需登录态，Apifox 安全定义为 cookie `AIUSS`。私信列表继续使用 `/api/v1/direct_message/conversations`。

请求 query：

- `block*`: string，枚举 `world_apply`、`follow`、`interaction`
- `pn`: integer，最小 `1`，默认 `1`
- `rn`: integer，最小 `1`，最大 `100`，默认 `20`

响应 `data`：

- `list*`: `MessageNotificationItem[]`
- `total*`: integer
- `pn*`: integer
- `rn*`: integer

错误码：

- `4004`：`block` 非法
- `10001`：用户未登录

实现状态：已封装在 `MessagesV1Api.notifications(block,pn,rn)`；消息页三个入口分别传 `world_apply`、`follow`、`interaction`，不再发送旧的 `category=system/follower/comment`。

### POST `/api/v1/message/read`

标记消息中心中的非私信通知已读。需登录态，Apifox 安全定义为 cookie `AIUSS`。传 `notification_id` 时只标记单条；否则按 `block` 标记。私信会话已读继续使用 `/api/v1/direct_message/read`。

请求 body：

- `notification_id`: string，单条通知 id；传入后优先按单条标记已读
- `block`: string，未传 `notification_id` 时生效，枚举 `world_apply`、`follow`、`interaction`、`all`

响应 `data`：空对象。

错误码：

- `4004`：`block` 非法
- `10001`：用户未登录

实现状态：已封装在 `MessagesV1Api.markNotificationsRead(block,notificationId)`；页面进入通知分组时按对应 `block` 标记已读，不再调用旧的 `/api/v1/message/notifications/read`。

## Report 接口

### POST `/api/v1/report/create`

提交举报。登录或未登录用户均可提交；携带有效 session 时服务端记录 `reporter_uid`，未登录时保存为空字符串。

客户端运行时 header 会经 `GenesisApi` 自动注入。服务端读取并 trim / 截断这些客户端元数据：

- `device-id`：最长 128 字符
- `app-id`：最长 64 字符
- `app-version`：最长 64 字符
- `app-platform`：最长 32 字符

请求 body：

- `target_type*`: string，举报对象类型，枚举 `origin`、`world`、`tick`、`message`、`discuss`
- `target_id*`: string，举报对象业务 id；`message` 当前按 `global_message_id` 原样记录，不做存在性校验
- `content*`: string，举报内容；服务端 trim 后不能为空，最长 1000 字符

请求示例：

```json
{
  "target_type": "origin",
  "target_id": "o_A1B2C3",
  "content": "内容疑似违规"
}
```

响应 `data`：

- `report_id*`: string

响应示例：

```json
{
  "err_no": 0,
  "err_msg": "succ",
  "data": {
    "report_id": "rpt_X9KQ4M2A1B2C"
  }
}
```

错误码：

- `4004`：`target_id` 为空或 `content` 为空
- `20801`：`target_type` 不支持
- `20802`：`content` 超过 1000 字符

## Feedback 接口

### POST `/api/v1/feedback/create`

提交产品反馈。登录或未登录用户均可提交；携带有效 session 时服务端记录 `feedbacker_uid`，未登录时保存为空字符串。本接口没有 `target_type` / `target_id`。

客户端运行时 header 会经 `GenesisApi` 自动注入。服务端读取并 trim / 截断这些客户端元数据：

- `device-id`：最长 128 字符
- `app-id`：最长 64 字符
- `app-version`：最长 64 字符
- `app-platform`：最长 32 字符

请求 body：

- `content*`: string，反馈内容；服务端 trim 后不能为空，最长 1000 字符

请求示例：

```json
{
  "content": "希望增加夜间模式"
}
```

响应 `data`：

- `feedback_id*`: string

响应示例：

```json
{
  "err_no": 0,
  "err_msg": "succ",
  "data": {
    "feedback_id": "fbk_X9KQ4M2A1B2C"
  }
}
```

错误码：

- `4004`：`content` 为空
- `20901`：`content` 超过 1000 字符

## Collect 接口

### POST `https://collect.worldo.ai/api/v1/collect`

批量提交客户端行为事件。客户端在事件发生时先写入独立 SQLite 队列；冷启动的 `startup_first_report` 和 `launch_startup` 在 Collect recorder 准备完成后立即记录，早于 `runApp` 和 Firebase/Telemetry 完整初始化。Telemetry 初始化完成后再由独立上传器消费；每次按 FIFO 最多领取 100 条，客户端批次同时限制为 256 KiB。只有收到 2xx、有效 JSON 对象且 `err_no=0` 后才删除；所有未确认成功的事件保留原 `event_id` 和内容并恢复待发送。HTTP 400/413/422 可拆批重试，失败单条和超限单条仍保留；不再写入会被清理的内存 dead letter。失败记录移到队尾，给后续未尝试事件发送机会。

请求 header 在实际上传时按事件入队时保存的身份和环境快照生成；不同上下文分批，重新登录不改写旧事件的 UID：

- `X-Platform`: `android` 或 `ios`
- `X-App-Version`: 事件发生时的 App version name
- `x-app-environment`: `production` 或 `test`
- `X-Device-ID`: 当前设备 ID；允许匿名事件明确省略
- `X-UID`: 事件发生时已登录用户 uid；未登录或允许匿名事件不传

请求 body：

- `events*`: array，本批事件，按本地入队顺序排列；客户端默认最多 100 条，接口原约定上限为 500 条
- `events[].event_id*`: string，客户端生成的 UUID v4；重试保持不变，供服务端幂等去重
- `events[].action_type*`: string，事件类型，例如 `pageview`、`event`、`monitor`、`pay_event`；`api_req_start`、`api_req_success`、`api_req_fail_tech`、`api_req_fail_biz` 使用 `monitor`
- `events[].action*`: string，页面名或事件名
- `events[].app_timestamp*`: integer，事件发生时的本地 Unix 毫秒时间戳，不是上传时间
- `events[].object1*`: string，第一个业务对象；无值传 `""`
- `events[].object2*`: string，第二个业务对象；无值传 `""`。接口监控使用同一逻辑请求的 `request_id` 关联 start 与终态
- `events[].object3*`: string，第三个业务对象；无值传 `""`
- `events[].object4*`: string，第四个业务对象；无值传 `""`。接口监控 start 传 `"0"`，终态使用不带单位后缀的整数毫秒字符串记录最终一次实际 transport send 的耗时
- `events[].ext_data*`: string，扩展信息；无值传 `""`。接口失败传脱敏后的 JSON 字符串，可包含 `reason`、`message`、`native_code`、`upstream_status`、`upstream_path`、`retry_count`；不得包含请求 header、query、body、完整响应 body 或 stack trace
- App 生命周期事件使用 `action_type: "event"`：`app_background.object1` 为空；与其配对的 `app_foreground.object1` 为本次后台停留时长，使用不带单位后缀的非负整数毫秒字符串。冷启动不产生 `app_foreground`
- 客户端接口监控使用 `api_req_start`、`api_req_success`、`api_req_fail_tech`、`api_req_fail_biz`。持续后台轮询接口不产生接口监控事件：`GET /api/v1/message/unread`、`GET /api/v1/direct_message/conversations`、`GET /api/v1/direct_message/list`；`/api/v1/collect` 永久排除。`/api/v1/app/config` 及三个启动关键 Gateway 接口固定上报，其他普通业务接口按启动级采样开关决定。

请求示例：

```json
{
  "events": [
    {
      "event_id": "813b862f-e8c7-44a5-92ea-5fe5cb4df9ab",
      "action_type": "pageview",
      "action": "home_my_worlds",
      "app_timestamp": 1784692855123,
      "object1": "",
      "object2": "",
      "object3": "",
      "object4": "",
      "ext_data": ""
    }
  ]
}
```

成功判定：HTTP 状态码为 2xx，且 JSON 响应中的 `err_no` 为数值 `0` 或字符串 `"0"`。非 2xx、超时、网络异常、无效 JSON 或非零 `err_no` 都视为该次请求失败，不支持在一个响应内确认部分事件。客户端因大小限制或请求被拒绝而拆成多个子请求时，每个成功子批次会按 `event_id` 独立确认，只重试尚未成功的部分；本地删除失败的已成功事件保持 in-flight。写库超时后的迟到记录会与内存副本按同一 ID 归并，避免两个队列再次发送。 内存备用队列不再按原 300 条阈值淘汰未确认数据；数据库恢复后补写入库。若数据库始终不可写且进程退出，内存记录仍有丢失风险，详见 [失败保留策略](/Users/long/Project/GenesisApp_2/genesis_app/docs/collect-failure-retention.md)。

响应示例：

```json
{
  "err_no": 0,
  "err_msg": "succ",
  "data": {}
}
```

## Upload 接口

### POST `/api/v1/upload/image`

上传图片到阿里云 OSS。需登录态，Apifox 安全定义为 cookie `AIUSS`。请求体类型为 `multipart/form-data`，文件字段名为 `file`。

服务端行为：

- 将客户端上传的图片文件保存到阿里云 OSS，返回对外可访问 URL。
- 服务端限制文件体积 `<= 10MiB`。
- 扩展名仅支持 `jpg/jpeg/png/gif/webp`。
- `object_key` 形如 `<pathPrefix>/<yyyyMMdd>/<snowflake>.<ext>`。

请求 body：

- `file*`: binary，`multipart/form-data` 文件字段

响应 `data`：`UploadImageResult`。

响应示例：

```json
{
  "err_no": 0,
  "err_msg": "succ",
  "data": {
    "url": "https://cdn.example.com/uploads/20260526/1234567890.jpg",
    "object_key": "uploads/20260526/1234567890.jpg"
  }
}
```

错误码：

- `10001`
- `20501`
- `20502`
- `20503`
- `20504`

## 当前代码对齐状态

截至 2026-08-10，本文档覆盖的 53 个接口已完成主要 HTTP 契约对齐；Collect 已切换为 SQLite 持久化队列和 `events[]` 批量协议，其余接口继续按各自文档维护当前封装、本地 mock 与测试：

| Apifox 接口 | 当前实现状态 |
| --- | --- |
| `POST /api/v1/app/version/check` | 已新增 `AppV1Api.versionCheck`，body 使用 `app_id/platform/channel/version_name/version_code/device_id/uid`，响应消费 `need_upgrade/force_upgrade/latest_version_name/latest_version_code/min_version_code/upgrade_type/title/content/download_url/store_url/package_size/package_md5/can_ignore`；`ForceUpgradeGate` 会在启动、回前台和登录态变化后检查，强更命中时阻断继续使用；本地 mock 默认返回无升级。 |
| `POST /api/v1/user/oauth/google` | `UserV1Api.googleAuth` 与 `GenesisApi.loginWithGoogle/loginWithIdentity` 已走 `/user/oauth/google`，body 使用 `id_token/nonce/name/avatar`。 |
| `POST /api/v1/user/oauth/apple` | `UserV1Api.appleAuth` 与 `GenesisApi.loginWithApple/loginWithIdentity` 已走 `/user/oauth/apple`，body 使用 `id_token/nonce/name/avatar`；不再向后端发送 `firebase_id_token`。 |
| `POST /api/v1/user/logout` | `GenesisApi.logout` 已走 `/user/logout`。 |
| `POST /api/v1/user/delete` | `UserV1Api.deleteAccount` 与 `GenesisApi.deleteAccount` 已走 `/user/delete`，Settings 确认后由 `BackendAuthCoordinator.deleteAccount` 用清理前 token 后台提交并立即清本地登录态。 |
| `GET /api/v1/user/info` | `UserV1Api.info` 支持可选 `uid` query；`bindDevice/hasAuthenticatedSession/getUser/getDisplayUserCode` 已切到该接口。 |
| `POST /api/v1/user/follow` | `FollowV1Api.follow` body 已改为 `target_uid`，响应按空对象处理。 |
| `POST /api/v1/user/unfollow` | `FollowV1Api.unfollow` body 已改为 `target_uid`，响应按空对象处理。 |
| `GET /api/v1/user/following` | 已新增 `FollowV1Api.following(uid,pn,rn)`。 |
| `GET /api/v1/user/followers` | 已新增 `FollowV1Api.followers(uid,pn,rn)`。 |
| `GET /api/v1/user/world-history-settings` | 已新增 `UserV1Api.worldHistorySettings`，解析当前生效值、持久化值、来源和降级状态；Developer Page 仅在测试环境且存在完整登录 session 时显示入口。 |
| `PUT /api/v1/user/world-history-settings` | 已新增 `UserV1Api.updateWorldHistorySettings`，JSON body 原子提交 `high_watermark/low_watermark`，Developer Page 在提交前校验 Apifox 范围。 |
| `DELETE /api/v1/user/world-history-settings` | 已新增 `UserV1Api.resetWorldHistorySettings`，无 body，成功后用服务端返回的默认生效值刷新输入框。 |
| `GET /api/v1/world/list` | `WorldV1Api.list` query 已使用 `scene/tag/origin_id/uid/keyword/pn/rn`；自有数据只传 `scene=mine`，指定用户数据传 `scene=uid&uid=...`，标签数据传 `scene=tag&tag=...`；首页和个人 world 列表可消费 `list[].info + stats`；详情入口使用 `info.definition_version/default_map_location_id` 立即挂载不可交互的 Tilemap，地图返回后即可渲染，detail 返回后再补齐 location tree 与交互。 |
| `GET /api/v1/world/info` | 已新增 `WorldV1Api.info(worldId)` 与 `GenesisApi.getWorldInfo(wid)`，query 使用 `world_id`；响应消费 `info + stats`，不期待 `relation_status/characters/locations/ticks`。 |
| `GET /api/v1/world/detail` | `WorldV1Api.detail` query 只使用 `world_id`；详情 mapper 消费 `info.definition_version`、`info.last_chat_location_id`、`info.metric`、`relation_status` 与 `locations[].location_description/location_paragraph/location_timestamp/dialogue`；`last_chat_location_id` 用于进入 World 时初始化地图和 Location List 的 Recent Message 标签，本次页面会话内再由发送成功后的内存临时记录覆盖；地图 JSON 按需通过 `/world/map` 获取，完整 tick 列表通过 `/world/tick/list` 获取。 |
| `GET /api/v1/world/map` | 已新增 `WorldV1Api.map(worldId,locationId)` 与 `GenesisApi.getWorldMap(...)`，query 使用 `world_id/location_id`；响应映射为 `TilemapDefinition`，其中 `tile_types` 为瓦片类型到线上图片 URL 的映射，`map_json` 使用 `width/height` 描述网格尺寸，`tiles[]` 使用 `x/y/type/shadow/location_id?` 描述瓦片；并明确支持旧地图的空对象 `data={}`。 |
| `GET /api/v1/world/tick/list` | `WorldV1Api.tickList(worldId,pn,rn)` 与 `GenesisApi.getWorldTicks(wid,limit,offset)` 使用 `world_id/pn/rn`；服务端只返回 `status=50 (p2_done)` 的最新完成 tick，客户端完整保留 `sub_tick_no`、`tick_result.current_time`、段落可见性/线索/整数指标增量及 location groups。 |
| `GET /api/v1/world/origin_progress` | 已新增 `WorldV1Api.originProgress(uid,originId)`，query 使用 `uid/origin_id`，响应消费 `world_id/tick_cnt`；origin discuss loader 会用该接口补齐每条评论作者在当前 origin 下的 world 与 tick 进度。 |
| `POST /api/v1/world/tick` | 新契约替代旧 progress 触发接口；客户端应提交 `{ "world_id": "<world_id>" }` 并消费 `world_id/tick_cnt/last_tick`。 |
| `GET /aitown-chat/api/ulocation` | `ChatroomHttpApi.getUserLocations(worldId)` query 使用 `world_id`，响应消费 `locations[].characters[]`，角色字段为 `char_id/player_uid/player_username/name/location_id`；`WorldChatroomService` 用 `player_uid` 识别真实用户并刷新所在 location，本地 mock 从 world detail 角色列表生成同形状响应。 |
| `GET /aitown-chat/internal/world/messages` | `ChatroomHttpApi.getWorldMessages(worldId)` 保留旧 world 级恢复/诊断能力，响应消费 `locations[].location_id/messages[]`；location chat 页的 initial、older 和 gap 不直接依赖该接口。旧 DTO 继续解析 `global_message_id/message_id/location_message_id/message_type/current_time/tick_no/created_at`。 |
| `GET /aitown-chat/api/messages` | `ChatroomHttpApi.getLegacyMessages(worldId,locationId,since,limit)` 显式保留旧扁平消息接口，供兼容/诊断使用；旧 typed JSON timeline payload 和图片规则不变。零游标记录中仅 `tick` 保留 world-message 排序/双游标语义，`user_enter_location/story_events/characters_moved` 只兼容入队、展示与后备去重。 |
| `GET /aitown-chat/api/v2/messages` | `ChatroomHttpApi.getMessages(worldId,locationId,since,limit)` 已切换 V2 per-location 路径；共享 `ChatroomV2Message` 保留 `type/stream_type/ts`、完整 ID、sender、`client_msg_id/message_type/min_app_version/created_at`、原始 `payload` 和数字 `err_no`。`ChatroomHttpMessage` 额外暴露 `businessType/streamType/clientMsgId/minAppVersion/payload/v2TickPayload`。分页和 `newest_message_id` 均严格使用当前地点 `location_message_id`。合法/回退 Tick 均保留正游标；SQLite v4 定向清除旧的游标零 `tick/story_events/characters_moved` 行，新的 canonical Tick 只写一条缓存行。Local mock 支持相同路由、字段、倒序分页和地点 newest 语义。 |
| `POST /aitown-chat/internal/tick/lock` | 已新增 `ChatroomHttpApi.lockWorld(worldId)`，按 Apifox 同时发送 query `world_id` 与 multipart form `world_id`，响应消费 `locked`。 |
| `GET /aitown-chat/internal/tick/progress` | 已新增 `ChatroomHttpApi.tickProgress(worldId)`，响应消费 `progress/pending_messages/active_llm_calls`。 |
| `POST /aitown-chat/internal/tick/unlock` | 已新增 `ChatroomHttpApi.unlockWorld(worldId)`，multipart form 发送 `world_id`，响应消费 `unlocked`。 |
| `POST /aitown-chat/internal/narrator/write` | 已新增 `ChatroomHttpApi.writeNarrator(worldId,tickId,locationGroups)`，body 使用 `world_id/tick_id/location_groups`，响应消费 `message_id`；本地 mock 会写入 narrator 消息。 |
| `GET /api/v2/search` | `SearchV1Api.search` 保留调用入口但返回完整 `SearchV2Response`；继续发送 `keyword/type/pn/rn`，完整消费三类分页块及所有 item 字段；三类都保留 `matches[].field/highlight_ranges`，只有 Origin 的 `character_name` 命中带 `character_id`，Origin 额外保留 `characters` 和 `matches_truncated`；范围使用 UTF-16 code unit。 |
| `GET /api/v1/origin/list` | `OriginV1Api.list` query 已使用 `scene/tag/tag_id/keyword/uid/pn/rn`；自有数据只传 `scene=mine`，指定用户数据传 `scene=uid&uid=...`，标签数据传 `scene=tag&tag=...`；origin 页面和主 `getOrigins/getMyLaunchedOrigins` 可消费 `list[].info + stats`；详情入口使用 `info.definition_version/default_map_location_id` 立即挂载不可交互的 Tilemap，地图返回后即可渲染，detail 返回后再补齐 location tree 与交互；首页 popular 会优先消费 `list[].discusses` 作为最新 2 条讨论预览，本地 mock 仅默认/`popular` 场景返回该字段。 |
| `GET /api/v1/origin/feed` | `OriginV1Api.feed` 使用 `start_score/rn`；Origin 页仅 For you 使用该接口，刷新传 `0`，分页严格复用响应 `next_score`，并以 `has_more` 和游标前进共同决定是否继续；`list[].info` 保留 `definition_version/default_map_location_id`，详情 loading 阶段据此直接挂载不可交互的默认 2.5D Tilemap，地图渲染不等待 detail。 |
| `POST /api/v1/origin/feed/exposure` | `OriginV1Api.reportFeedExposure` 提交 `origin_ids`；Origin 页仅在封面成功渲染后，按列表真实内容视口内 30% 可见面积和连续 1.5 秒可见时长采集；占位、加载中、加载失败、低于阈值或快速经过均不采集，本地按页面生命周期去重。 |
| `GET /api/v1/origin/hot_tags` | 已新增 `OriginV1Api.hotTags`，响应消费 `data.list` 字符串数组；`OriginPage` 固定首个 `For you` tab，其余 tabs 来自热门标签接口并缓存在本地，本地 mock 返回同形状数据。 |
| `GET /api/v1/origin/my_launch_preset_characters` | `OriginV1Api.myLaunchPresetCharacters(originId,limit)` 与 `GenesisApi.getMyLaunchPresetCharacters(originId,limit)` 的 query 使用 `origin_id/limit`；Opening Sheet 固定请求 `limit=5`，服务端先按 `last_active_at DESC` 排序再限制数量，客户端按响应顺序展示；响应映射为 `OriginMyLaunchPresetCharacter` 列表并保留 `ImageResource`。 |
| `GET /api/v1/origin/info` | 已新增 `OriginV1Api.info(originId)` 与 `GenesisApi.getOriginInfo(oid)`，query 使用 `origin_id`；响应消费 `info + stats`，不期待 `characters/locations/ticks`。 |
| `GET /api/v1/app/config` | `AppV1Api.config` 在启动早期读取本地登录 UID 后请求，有真实非 guest UID 时传可选 query `uid`，未登录、读取失败或超时时不传；`show_opening_sheet` 决定 Origin Detail Opening Sheet 的首帧展开状态，失败或超时按 `false` 兜底。 |
| `GET /api/v1/origin/detail` | `OriginV1Api.detail` query 使用必填 `origin_id`；详情 mapper 保留新版 `OriginDetailInfo`、完整 stats、nullable 顶层 `init_location_group`、`characters[].is_recommend`、location 层级/时间/总结/2.5D `x/y`、ImageResource sidecar，以及 tick 的 `sub_tick_no/current_time/visibility/visible_to/clue/character_deltas`。本接口不再承载 Opening Sheet 展示配置，不依赖 `location_description`，也不为新版 tick 人工补 `location_groups`；旧响应实际携带这些字段时仍可兼容读取。详情 Opening、location chat 预览和 launch 初始地点优先使用顶层 group；`nar_pic/image` 作为图片消息展示。 |
| `GET /api/v1/origin/map` | 已新增 `OriginV1Api.map(originId,locationId)` 与 `GenesisApi.getOriginMap(...)`，query 使用 `origin_id/location_id`；响应映射为 `TilemapDefinition`，其中 `tile_types` 为瓦片类型到线上图片 URL 的映射，`map_json` 使用 `width/height` 描述网格尺寸，`tiles[]` 使用 `x/y/type/shadow/location_id?` 描述瓦片；并明确支持旧地图的空对象 `data={}`。 |
| `GET /api/v2/origin/foredit` | `OriginV2Api.forEdit(originId)` 使用 `origin_id` query，并按嵌套 `OriginDetail` 消费；`characters[].is_recommend` 以 `0/1` integer 回填角色推荐状态。`EditOriginPage` 直接从该响应回填 Basics、Characters、Locations、Opening 和兼容 tick Opening，不再追加请求 `/api/v1/origin/detail`。新契约未返回的旧平级 `setting/events` 仅在响应实际包含或用户明确修改时随 V2 update 提交；`Character` 未返回旧 `bio/description` 时，未编辑的空 Biography 也不随 update 回写，避免普通编辑把服务端已有值清空。 |
| `POST /api/v1/origin/create` | 当前 `OriginV1Api.create` 已发送 `origin_name/origin_version/brief/setting/events/tags/metric/started_at/tick_duration_time/cover/characters/locations`，但尚未暴露新契约中的 `definition_version/map_url/tile_types`；高层 `GenesisApi.createOrigin` 已兼容轻量 `OriginUpsertResp`。 |
| `POST /api/v1/origin/update` | 当前 `OriginV1Api.update` 已发送 `origin_id/origin_name/origin_version/brief/setting/events/tags/metric/started_at/tick_duration_time/cover/characters/locations/update_notes/deleted_char_ids/deleted_location_ids`，但尚未暴露新契约中的 `definition_version/map_url/tile_types`；高层 `GenesisApi.updateOrigin` 已兼容轻量 `OriginUpsertResp`。 |
| `POST /api/v2/origin/create` | 已新增 `OriginV2Api.create` / `GenesisApi.createOriginV2`，完整支持含 `characters[].is_recommend` 的 V1 create body 与 `init_location_group`。Create 页面在同步成功且返回非空 `origin_id` 后立即展示创建成功，不等待异步地图状态；本地 mock 覆盖 definition version 2、Opening 保存与 processing 状态。 |
| `POST /api/v2/origin/update` | 已新增 `OriginV2Api.update` / `GenesisApi.updateOriginV2`，完整支持含 `characters[].is_recommend` 的 V1 update body、删除列表和完整 `init_location_group`；Edit 页面继续通过 V1 info 等待状态 10。本地 mock 返回递增版本、回显 Opening，并在 info 轮询中确定性模拟 `20 -> 10`。 |
| `POST /api/v1/origin/launch` | `OriginV1Api.launch` body 使用 `origin_id/preset_character_id/custom_role`；详情页发送 preset 或 custom 二选一 payload，不提供 preset 编辑或 override 调用链，并消费响应 `world_id`。 |
| `GET /api/v1/discuss/list` | `DiscussV1Api.list` 已使用 `biz_type=1`、`biz_id/pn/rn`，并消费 `list[].comment/latest_replies/top_total/total_all`；本地 mock 会按业务对象分页并为每条顶级评论返回最新 3 条回复。 |
| `GET /api/v1/discuss/replies` | 已新增 `DiscussV1Api.replies(rootDiscussId,pn,rn)`，query 使用 `root_discuss_id/pn/rn`，响应消费 `list/total/pn/rn`；本地 mock 会按 `root_discuss_id` 过滤并按创建时间倒序分页。 |
| `POST /api/v1/discuss/post` | `DiscussV1Api.post` 已支持顶级评论与回复统一入口，body 使用 `biz_type/biz_id/content/images/root_discuss_id/parent_discuss_id`，响应消费 `discuss_id/root_discuss_id/level`。 |
| `POST /api/v1/discuss/delete` | `DiscussV1Api.delete` 已改为 `/discuss/delete` + `discuss_id`，响应按空对象处理。 |
| `POST /api/v1/discuss/like` | `DiscussV1Api.like` 已改为 `discuss_id`，响应按空对象处理；本地 mock 幂等维护 `is_liked/like_cnt`。 |
| `POST /api/v1/discuss/unlike` | `DiscussV1Api.unlike` 已新增 `/discuss/unlike` + `discuss_id`，响应按空对象处理；本地 mock 幂等维护 `is_liked/like_cnt`。 |
| `POST /api/v1/direct_message/send` | `DmV1Api.send` 已改为 `/direct_message/send`，body 使用 `peer_uid/content`，响应消费 `message/conversation`。 |
| `GET /api/v1/direct_message/conversations` | `DmV1Api.conversations` 已替代旧 `/dm/chatlist`，query 支持全量 `pn/rn` 或增量 `after_message_id`；响应消费 `list/total/pn/rn/next_after_message_id`；本地 mock 支持全量分页、增量更新、增量插入和空增量。 |
| `GET /api/v1/direct_message/list` | `DmV1Api.list` 已替代旧 `/dm/messagelist`，query 使用 `peer_uid/pn/rn`，响应消费 `list/total/pn/rn`；`ChatPage` 已接本地 DB、5 秒轮询 merge、顶部滚动分页和行级渲染。 |
| `POST /api/v1/direct_message/read` | `DmV1Api.markRead` 已改为使用 `peer_uid`，不再提交 `conversation_id/last_read_seq`。 |
| `GET /api/v1/direct_message/unread` | 已新增 `DmV1Api.unread`，响应消费 `unread_cnt`。 |
| `GET /api/v1/message/unread` | `MessagesV1Api.unreadSummary` 已改用消息页未读统计接口，响应消费 `world_apply_unread/follow_unread/interaction_unread/direct_message_unread/total_unread`。 |
| `GET /api/v1/message/notifications` | `MessagesV1Api.notifications` 已改为必传 `block` query，枚举 `world_apply/follow/interaction`；页面入口已从旧 `system/follower/comment` 映射为 Apifox 的三个 block。 |
| `POST /api/v1/message/read` | `MessagesV1Api.markNotificationsRead` 已改为 `/message/read`，body 使用 `block` 或 `notification_id`，不再提交旧 `category/notification_ids`。 |
| `POST /api/v1/report/create` | 已新增 `ReportV1Api.create`，body 使用 `target_type/target_id/content`，响应消费 `report_id`；World、Worldo、用户详情页和 location chat 长按菜单已接入，其中 message report 的 `target_id` 使用 `global_message_id`；通过共享 `GenesisApi` runtime header path 自动带上 `device-id/app-id/app-version/app-platform/authorization`；本地 mock 校验 `target_type`、空 `target_id/content` 与 1000 字符长度限制，并为用户详情页 report 补充接受 `target_type=user`。 |
| `POST /api/v1/feedback/create` | 已新增 `FeedbackV1Api.create`，body 使用 `content`，响应消费 `feedback_id`；通过共享 `GenesisApi` runtime header path 自动带上 `device-id/app-id/app-version/app-platform/authorization`；本地 mock 校验空 `content` 与 1000 字符长度限制。 |
| `POST /api/v1/direct_message/block` | 已新增 `DmV1Api.block`，body 使用 `target_uid`。 |
| `POST /api/v1/direct_message/unblock` | 已新增 `DmV1Api.unblock`，body 使用 `target_uid`。 |
| `GET /api/v1/direct_message/blocks` | 已新增 `DmV1Api.blocks`，响应消费拉黑用户分页列表。 |
| `POST /api/v1/upload/image` | 已新增 `UploadV1Api.image`，multipart 字段名固定为 `file`，响应消费 `url/object_key`；头像上传已改用新接口，本地 mock 返回 `https://mock.local/uploads/...`。 |

当前 v1 响应处理：

- `handleV1ResponseErrNo` 识别 `err_no` / `errNo`。
- 成功时返回 `data`。
- 失败消息优先读取 Apifox 的 `err_msg`，并兼容旧的 `err_str` / `errStr`。
- 响应对象 key 仍会从 camelCase 规范化成 snake_case，用于兼容旧 mock 和历史接口。

为降低迁移风险，代码仍保留若干兼容能力：

- world 详情 mapper 只消费 Apifox 的 `info/stats/characters/locations/ticks`；origin 详情 mapper 暂保留旧字段兼容。
- 关系字段在 mock 中同时保留 `is_followed` 与历史 `i_followed`，但 Apifox 新接口按 `is_followed` 生成。
- 多数 Apifox 页面未声明 headers/security；当前客户端仍按应用运行时注入 `app-id`、`app-version`、`app-platform`、`device-id`、`authorization: Bearer <token>`，其中 report 和 feedback 页面明确声明会读取这些客户端元数据 header。

### Apifox 未覆盖但当前 v1 已封装的接口

用户与关系：

- `POST /api/v1/user/update`
- `GET /api/v1/user/profile`
- `GET /api/v1/user/origins`
- `GET /api/v1/user/worlds`
- `GET /api/v1/user/relations`
- `POST /api/v1/users/relations/status`

Origin：

- `GET /api/v1/origin/versionlist`
- `POST /api/v1/origin/publish`
- `POST /api/v1/origin/del`

World：

- `POST /api/v1/world/apply`
- `GET /api/v1/world/apply/list`
- `POST /api/v1/world/apply/review`
- `POST /api/v1/world/join`
- `POST /api/v1/world/synclastorigin`
- `POST /api/v1/world/close`
- `POST /api/v1/world/del`

消息、首页、通用：

- `GET /api/v1/messages/followers`
- `GET /api/v1/search/suggest`
- `GET /api/v1/home`
- `GET /api/v1/home/following`
- `POST /api/v1/common/upload`
- `POST /api/v1/common/drafts`
- `GET /api/v1/common/drafts`
- `POST /api/v1/common/drafts/del`
- `POST /api/v1/common/devices/register`

### Apifox 未覆盖但当前仍保留的旧 HTTP 接口

这些接口不属于本文档覆盖的 Apifox `/api/v1` 接口。当前代码只在对应功能尚无 Apifox 契约时继续保留，已不再用于本文档覆盖的登录、用户信息、origin/world 列表详情与 world tick 接口：

- `POST /api/origins`
- `POST /api/worlds/launch`
- `POST /api/worlds/{wid}/join-requests`
- `GET /api/search`
- `GET /api/characters`
- `POST /api/tick`
- `GET /api/points/{pointId}/messages`
- `POST /api/points/{pointId}/messages/enqueue`
- `GET /health`


## Pro 会员商品列表（2026-09-08 核对）

来源：[Apifox 会员商品列表](https://app.apifox.com/link/project/8297783/apis/api-512137864)，使用最新 OpenAPI 的 `/api/v1/membership/products`、`MembershipProductListResp`、`MembershipProductInfo` 核对。

- `GET /api/v1/membership/products?provider=google|apple`，需要登录，复用现有 Authorization 与 Gateway 签名链路；不发送文档中的调试身份头。
- 响应为 `{err_no, err_msg, data: {list: [...]}}`；成功但无配置时 `list=[]`。业务错误 `10001` 未登录、`4004` 参数错误、`5000` 服务不可用，继续使用统一错误处理。
- 每项必含 `plan_code`（`pro_monthly`/`pro_yearly`）、`provider`、`store_product_id`、`billing_months`（1/12）、`monthly_gems_cent`、`config_version`、`sale_enabled`。Google 还必含 `base_plan_id`，可选 `offer_id`；Apple 不返回 base plan。
- `monthly_gems_cent` 是每个会员月的额度，100 cent = 1 Gem；年付也是逐月发放。月付和年付允许配置不同额度，本次保留原有权益文案。
- `sale_enabled=false` 表示不开放新购买，不代表已有会员失效。
- 本接口不含价格及 offer token。商品列表由 `GenesisApi.v1.membership.products` 读取，再从商店 SDK 查询本地化价格。Google 精确匹配商品 ID、base plan 和可选 offer，不将同一商品下首个方案当作默认答案；配置 offer 不可用时不擅自换成基础方案。
- Google 多阶段优惠使用与付费周期匹配的常规续费价格；年付卡片填入按商店年价计算的月均价，底部填入商店返回的完整年价。双方价格币种和月额度相同、无首购阶段时计算年付折扣。
- 共享 `ProSubscriptionContent` 同时覆盖钱包页和购买弹层，保留原有布局、样式、权益文案及两个套餐卡片，仅绑定真实价格与折扣数据；不增加加载、错误、登录、空列表、停售或首购优惠的 UI。缺少数据时金额和折扣文字留空，不回退到预览价格；账号切换会清空并重取，旧请求不能覆盖新账号状态。缺少商品或价格时，点击原按钮可重新查询。
- `sale_enabled` 仅用于业务拦截，不改变按钮、卡片、文案或价格展示；停售配置仍查询对应商店价格。
- 钱包页和购买弹层初始仅加载当前 TAB，另一个 TAB 首次切换到时加载，后续切换复用已加载内容。
- 此步骤只接商品配置和价格展示，尚未接购买、恢复、购买确认或权益同步；按钮仍沿用未开通购买提示。其余既有静态权益图示不由这个接口确认。
- 本地 mock 仅返回契约允许的空列表，不伪造商店商品或价格。
