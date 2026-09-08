# APP 业务接口请求监控与报表口径

版本：1.0  
日期：2026-08-31  
适用范围：GenesisApp `/api/...` 业务 HTTP 接口

## 1. 文档目的

本文定义 APP 业务接口请求监控事件、成功/失败判定、技术错误码、服务端 `err_no` 归因以及报表计算口径。

本文供以下场景共同使用：

- 客户端埋点开发和联调；
- 数据仓库清洗和宽表建设；
- API 成功率、可用率、失败率和耗时报表；
- 技术失败、服务端内部失败和用户业务失败的归因；
- 按接口、错误类型、客户端版本等维度排障。

## 2. 最重要的状态码原则

### 2.1 HTTP 状态码和 `err_no` 是两套独立的码

服务端已经确认：

- HTTP 状态码只使用标准 HTTP 状态，例如 `1xx`、`2xx`、`3xx`、`4xx`、`5xx`；
- 所有应用层状态均通过响应体字段 `err_no` 返回；
- `1404`、`20201` 等服务端业务码不是 HTTP 状态码；
- 接口文档中把 `20201` 等 `err_no` 展示为“HTTP 状态码”的页面是错误展示，客户端和报表均不得按该展示处理。

标准响应 envelope：

```json
{
  "err_no": 0,
  "err_msg": "succ",
  "data": {}
}
```

### 2.2 两层失败与二级根因

事件首先按协议层分为：

| 层级 | 事件 | 含义 |
| --- | --- | --- |
| 请求成功 | `api_req_success` | HTTP、JSON、响应结构及 `err_no` 均成功 |
| 技术层失败 | `api_req_fail_tech` | HTTP、网络、TLS、请求构造、Gateway、JSON 或响应结构失败 |
| 应用层失败 | `api_req_fail_biz` | HTTP 成功且响应结构合法，但 `err_no != 0` |

注意：`api_req_fail_biz` 中的 `biz` 表示“应用层 `err_no` 失败”，不代表所有错误都是正常的产品业务校验。

例如：

- `biz_10006`：账号或密码错误，属于用户业务校验；
- `biz_3101`：数据库写入失败，属于服务端内部错误；
- `biz_5000`：系统异常，属于服务端内部错误；
- `biz_10008`：短信发送失败，属于外部依赖或服务端能力失败。

因此报表必须保留两个维度：

1. `failure_layer`：成功、技术层失败、应用层失败；
2. `root_cause_group`：客户端网络、HTTP、响应协议、Gateway、服务端内部、外部依赖、鉴权账号、正常业务规则等。

## 3. 埋点事件定义

只使用以下四个新 action。旧的 `api_request_start`、`api_request_success`、`api_request_failed` 不进入新版报表。

| action | 含义 | 是否终态 |
| --- | --- | --- |
| `api_req_start` | 一个逻辑接口请求开始 | 否 |
| `api_req_success` | 请求成功 | 是 |
| `api_req_fail_tech` | 技术层失败 | 是 |
| `api_req_fail_biz` | 应用层 `err_no` 失败 | 是 |

所有事件统一：

```text
action_type = monitor
```

### 3.1 公共字段

| 字段 | 内容 | 示例 | 报表用途 |
| --- | --- | --- | --- |
| `action` | 四个 action 之一 | `api_req_fail_biz` | 结果分类 |
| `action_type` | 固定为 `monitor` | `monitor` | 事件过滤 |
| `object1` | 接口 path，不包含 host 和 query | `/api/v1/world/list`、`/apix/v1/time` | 接口维度 |
| `object2` | APP 为本次逻辑请求生成的 `request_id` | `f5c...` | 关联 start 与终态 |
| `object3` | 结果码 | `biz_20201` | 核心错误维度 |
| `object4` | 耗时，单位 ms，字符串类型 | `318` | 延迟统计 |
| `ext_data` | 精简诊断 JSON，字段本身为 string 类型；无有效信息时为空字符串 | `{"reason":"json_decode"}` | 失败归因补充 |

`object2` 是客户端监控链路 ID，不应直接理解为服务端 access log 中的 request ID。若服务端以后下发独立 request ID，应使用新字段承载或在数据层单独映射。

### 3.2 各事件字段值

| action | `object3` | `object4` | `ext_data` |
| --- | --- | --- | --- |
| `api_req_start` | 空字符串 | `0` | 空字符串 |
| `api_req_success` | 空字符串 | 最后一次实际请求耗时 | 空字符串 |
| `api_req_fail_tech` | `tech_http_<HTTP状态码>` 或 `tech_client_<客户端码>` | 最后一次实际请求耗时 | 仅保留必要诊断信息 |
| `api_req_fail_biz` | `biz_<err_no>` | 最后一次实际请求耗时 | 可选的精简 `err_msg` |

## 4. 成功与失败判定流程

一个接口只有同时满足以下条件才上报 `api_req_success`：

1. 获得最终 HTTP 响应；
2. HTTP 状态为 `2xx`；
3. JSON 解析成功；
4. 响应顶层为合法对象；
5. 响应中存在可解析的 `err_no`；
6. `err_no == 0`；
7. 必要的响应处理没有抛出异常。

判定优先级如下：

```text
没有获得 HTTP 响应
  -> api_req_fail_tech
  -> object3 = tech_client_<code>

获得 HTTP 响应，但 HTTP 非 2xx
  -> api_req_fail_tech
  -> object3 = tech_http_<http_status>
  -> 不使用响应体 err_no 覆盖 HTTP 失败

HTTP 2xx，但 JSON 或响应结构不合法
  -> api_req_fail_tech
  -> object3 = tech_http_<http_status>
  -> ext_data.reason 记录具体响应问题

HTTP 2xx，响应结构合法，err_no != 0
  -> api_req_fail_biz
  -> object3 = biz_<err_no>

HTTP 2xx，响应结构合法，err_no == 0，必要处理成功
  -> api_req_success
  -> object3 = ""
```

### 4.1 判定示例

| 场景 | action | `object3` | `ext_data` 示例 |
| --- | --- | --- | --- |
| HTTP 500，响应体还有 `err_no=10001` | `api_req_fail_tech` | `tech_http_500` | 可为空 |
| HTTP 404 | `api_req_fail_tech` | `tech_http_404` | 可为空 |
| HTTP 200，非法 JSON | `api_req_fail_tech` | `tech_http_200` | `{"reason":"json_decode"}` |
| HTTP 200，顶层不是对象 | `api_req_fail_tech` | `tech_http_200` | `{"reason":"invalid_envelope"}` |
| HTTP 200，缺少 `err_no` | `api_req_fail_tech` | `tech_http_200` | `{"reason":"missing_err_no"}` |
| HTTP 200，`err_no` 无法解析 | `api_req_fail_tech` | `tech_http_200` | `{"reason":"invalid_err_no"}` |
| HTTP 200，`err_no=20201` | `api_req_fail_biz` | `biz_20201` | 可带精简 `err_msg` |
| HTTP 200，`err_no=0` | `api_req_success` | 空字符串 | 空字符串 |
| 请求超时且无 HTTP 响应 | `api_req_fail_tech` | `tech_client_1001` 至 `1004` | 通常为空 |

## 5. `api_req_fail_tech` 状态码

### 5.1 有 HTTP 响应：`tech_http_<status>`

只要本次业务请求获得合法的最终 HTTP 状态码，`object3` 就优先使用：

```text
tech_http_<HTTP状态码>
```

示例：

| `object3` | 含义 |
| --- | --- |
| `tech_http_200` | HTTP 成功，但 JSON、响应结构或必要处理失败 |
| `tech_http_301` | 最终暴露给 APP 的响应是 301，未成功完成重定向 |
| `tech_http_400` | HTTP Bad Request |
| `tech_http_401` | HTTP 未认证；现有 Session 静默刷新逻辑仍按 HTTP 401 处理 |
| `tech_http_403` | HTTP 禁止访问，不触发 HTTP 401 的静默刷新 |
| `tech_http_404` | HTTP 资源不存在；不得与业务 `err_no=1404` 混用 |
| `tech_http_429` | HTTP 限流 |
| `tech_http_500` | HTTP 服务端错误 |
| `tech_http_502` | 网关收到无效上游响应 |
| `tech_http_503` | 服务不可用 |
| `tech_http_504` | 网关超时 |

`1xx` 通常是中间响应，不应成为最终终态；若底层网络库最终暴露了合法 `100-599` 状态码，仍按真实值上报。

### 5.2 无 HTTP 响应：`tech_client_<code>`

客户端技术码是稳定的报表协议，已经使用的码不得改含义或复用。

#### 超时 `1001-1004`

| `object3` | 含义 | 建议根因组 |
| --- | --- | --- |
| `tech_client_1001` | 建立连接超时 | `client_timeout` |
| `tech_client_1002` | 发送请求超时 | `client_timeout` |
| `tech_client_1003` | 接收响应超时 | `client_timeout` |
| `tech_client_1004` | 无法识别阶段的超时 | `client_timeout` |

#### 网络连接 `1010-1019`

| `object3` | 含义 | 建议根因组 |
| --- | --- | --- |
| `tech_client_1010` | DNS 解析失败 | `client_network` |
| `tech_client_1011` | 网络不可用或不可达 | `client_network` |
| `tech_client_1012` | 连接被拒绝 | `client_network` |
| `tech_client_1013` | 连接被重置或连接丢失 | `client_network` |
| `tech_client_1014` | 连接提前关闭、broken pipe | `client_network` |
| `tech_client_1015` | 实际 HTTP/2、HTTP/3 或 QUIC 协议协商失败；正常回退 HTTP/1.1 或协议元数据缺失不算失败 | `client_protocol` |
| `tech_client_1019` | 其他已确认的连接类错误 | `client_network_other` |

#### TLS 与证书 `1020-1021`

| `object3` | 含义 | 建议根因组 |
| --- | --- | --- |
| `tech_client_1020` | TLS handshake 失败 | `client_tls` |
| `tech_client_1021` | 证书无效、不可信、过期或校验失败 | `client_tls` |

#### 取消 `1030`

| `object3` | 含义 | 建议根因组 |
| --- | --- | --- |
| `tech_client_1030` | 请求被客户端取消 | `client_cancelled` |

此码建议单独展示，不要直接算入“网络质量差”。页面退出、任务主动取消等正常行为也可能产生该码。

#### 请求构造 `1101-1104`

| `object3` | 含义 | 建议根因组 |
| --- | --- | --- |
| `tech_client_1101` | URI 或 query 构造失败 | `client_request_build` |
| `tech_client_1102` | 请求 header 准备失败 | `client_request_build` |
| `tech_client_1103` | 请求 body 序列化失败 | `client_request_build` |
| `tech_client_1104` | multipart 或文件读取失败 | `client_request_build` |

#### Gateway 本地认证 `1301-1399`

| `object3` | 含义 | 建议根因组 |
| --- | --- | --- |
| `tech_client_1301` | Gateway 设备或 APP 身份信息不完整 | `client_gateway` |
| `tech_client_1302` | 本地密钥或公钥不可用 | `client_gateway` |
| `tech_client_1303` | 本地签名失败 | `client_gateway` |
| `tech_client_1304` | Gateway 设备认证失败：获取 challenge、注册设备密钥或重新认证失败 | `client_gateway` |
| `tech_client_1305` | Gateway 服务端时间同步失败 | `client_gateway` |
| `tech_client_1399` | 其他 Gateway 认证失败 | `client_gateway_other` |

Gateway 内部访问上游接口失败时，原业务请求没有自己的 HTTP 响应，因此原业务请求的 `object3` 仍使用 `tech_client_13xx`；可用的实际 Gateway path 和 HTTP 状态分别写入 `ext_data.upstream_path`、`ext_data.upstream_status`，不能写成原业务请求的 `tech_http_xxx`。与此同时，`time/challenge/register` 自身会生成独立的接口监控链路，使用自己的 `/apix/...` path、request ID 和真实结果，不能与外层业务请求共用 request ID。

#### 未知错误 `1999`

| `object3` | 含义 | 建议根因组 |
| --- | --- | --- |
| `tech_client_1999` | 未知错误且没有 HTTP 响应 | `client_unknown` |

应持续监控该码占比。当某一种未知错误形成稳定规模后，应新增专用码，不应长期依赖 message 聚合。

## 6. `ext_data` 规范

`ext_data` 的字段类型是 string。内容有两种形式：

- 没有有价值的诊断数据：空字符串；
- 有诊断数据：JSON object 序列化后的字符串。

允许的精简字段：

| 字段 | 类型 | 使用条件 |
| --- | --- | --- |
| `reason` | string | 同一个 `object3` 仍需区分响应失败类型时使用 |
| `field` | string | 能明确定位到非法响应字段时使用 |
| `message` | string | 服务端 `err_msg` 或未知异常的精简信息确有排障价值时使用 |
| `native_code` | string | 原生网络库提供稳定错误码时使用 |
| `upstream_status` | number | Gateway 等准备流程的上游 HTTP 状态时使用 |
| `upstream_path` | string | 外层业务请求因 Gateway 前置流程失败时，记录实际失败的 `/apix/...` path |
| `retry_count` | number | 最终失败且确实发生过自动重试时使用；大于 0 才写入 |

当前响应失败 `reason`：

| `reason` | 含义 |
| --- | --- |
| `json_decode` | 响应不是合法 JSON |
| `empty_body` | JSON 接口响应体为空 |
| `invalid_envelope` | 顶层响应结构不合法 |
| `missing_err_no` | 响应缺少 `err_no`/`errNo` |
| `invalid_err_no` | `err_no` 无法解析为整数 |
| `response_processing` | 必要响应处理抛出异常 |

数据控制规则：

- 不上传 request/response 完整 body；
- 不上传完整 headers；
- 不上传堆栈；
- 不上传 URL query；
- 不上传 Authorization、token、password、secret、cookie；
- message 去除换行并做敏感信息替换；
- message 最长 200 字符；
- `object3` 已经表达的信息不要在 `ext_data` 重复；
- `message` 仅用于排障，不作为稳定报表分组键。

## 7. 服务端 `err_no` 报表字典

### 7.1 码段

以下是服务端提供文档中的码段。它们全部是 `err_no`，不是 HTTP 状态码。

| `err_no` 码段 | 服务端用途 | 建议报表域 |
| --- | --- | --- |
| `-1` | 未归一化错误或参数校验兜底 | `app_unclassified` |
| `0` | 成功 | `success` |
| `1404` | 历史通用资源不存在 | `business_resource` |
| `3100-3199` | 数据库通用错误 | `server_internal_db` |
| `4000-4999` | 通用请求、参数和框架错误 | 按具体码细分 |
| `5000-5999` | 系统与基础设施错误 | `server_internal_system` |
| `10000-10999` | 用户领域 | `business_user` 或按具体码细分 |
| `11000-11999` | CMS 管理领域 | `business_cms` |
| `20100-20199` | Origin 领域 | `business_origin` |
| `20200-20299` | World 领域 | `business_world` |
| `20300-20399` | 私信领域 | `business_direct_message` |
| `20400-20499` | Discuss 评论领域 | `business_discuss` |
| `20500-20599` | Upload 上传领域 | `business_upload` |
| `20600-20699` | Admin App Version 领域 | `business_admin_app_version` |
| `20700-20799` | Admin Review 领域 | `business_admin_review` |
| `20800-20899` | Report 举报领域 | `business_report` |
| `20900-20999` | Feedback 反馈领域 | `business_feedback` |
| `21000-21099` | Gem 钱包、购买、任务与消费领域 | `business_gem` |

未在服务端静态错误表中定义的具体数值，不应只根据号段自行推断精确含义。报表可以先落入对应 domain 的 `unknown_code`，等待服务端字典补齐。

同一个 `err_no` 可能对应多个错误变量，例如 `1404`。报表应结合 `object1 + err_no` 做接口上下文分析，不能依赖 `err_msg` 作为稳定分支。

### 7.2 已提供的具体错误码与根因分类

以下表格覆盖本次服务端文档中已经给出的具体静态错误码。

| `object3` | 服务端默认含义 | `root_cause_group` | 是否计入服务端质量异常 |
| --- | --- | --- | --- |
| `biz_-1` | 未归一化异常或参数校验兜底 | `app_unclassified` | 建议计入并单独告警 |
| `biz_1404` | 资源、用户、Origin 或 World 不存在 | `business_resource` | 否，按接口场景观察 |
| `biz_3101` | 数据库新增失败 | `server_internal_db` | 是 |
| `biz_3102` | 数据库更新失败 | `server_internal_db` | 是 |
| `biz_3103` | 数据库查询失败 | `server_internal_db` | 是 |
| `biz_3104` | 数据库删除失败 | `server_internal_db` | 是 |
| `biz_4000` | 服务端调用上游 HTTP 失败 | `server_dependency` | 是 |
| `biz_4001` | 服务端 JSON 解码失败 | `server_internal_contract` | 是 |
| `biz_4002` | 服务端 JSON 编码失败 | `server_internal_contract` | 是 |
| `biz_4003` | 服务端从 COS 下载文件失败 | `server_dependency` | 是 |
| `biz_4004` | 请求参数缺失、格式错误或不符合约束 | `business_parameter` | 通常否；异常突增时检查客户端契约 |
| `biz_4005` | 服务端调用登录 API 失败 | `server_dependency` | 是 |
| `biz_5000` | 系统或基础设施异常 | `server_internal_system` | 是 |
| `biz_10001` | 未登录或 Session 失效 | `auth_session` | 通常否；异常突增时检查 Session 链路 |
| `biz_10003` | 请求签名无效 | `auth_signature` | 是，需检查客户端/Gateway/服务端时间 |
| `biz_10004` | 手机号未注册 | `business_account` | 否 |
| `biz_10005` | 用户账号停用 | `business_account_state` | 否 |
| `biz_10006` | 账号或密码错误 | `business_validation` | 否 |
| `biz_10007` | 账号或验证码错误 | `business_validation` | 否 |
| `biz_10008` | 验证码短信发送失败 | `server_dependency` | 是 |
| `biz_10009` | 手机号已经注册 | `business_account` | 否 |
| `biz_10011` | 用户无权限 | `business_permission` | 否；异常突增时检查权限配置 |
| `biz_10012` | 用户已删除 | `business_account_state` | 否 |
| `biz_10013` | 用户已封禁 | `business_account_state` | 否 |
| `biz_10014` | Apple 身份迁移处理中 | `business_account_state` | 否 |
| `biz_10101` | 上传文件类型不支持 | `business_parameter` | 否 |
| `biz_10102` | 用户类型不支持 | `business_validation` | 否 |
| `biz_10103` | 密码长度不足 | `business_validation` | 否 |
| `biz_10104` | 不允许关注自己 | `business_rule` | 否 |
| `biz_10105` | 关注前需要解除拉黑 | `business_rule` | 否 |
| `biz_20201` | World ID 不存在或已软删除 | `business_resource` | 否，按接口场景观察 |

“是否计入服务端质量异常”是报表归因建议，不改变客户端 action。上述所有非零 `err_no` 仍然上报 `api_req_fail_biz`。

特别注意 `20502-20509`：服务端码段表把 `20500-20599` 分配给 Upload，但客户端 Gateway 验证链路也识别其中部分数值。数据字典必须结合 `object1`、实际响应来源和服务端最终契约归因，不能只按数值区间直接判定为 Upload。

### 7.3 `err_no=0`

`err_no=0` 表示应用层成功，但它不会写入成功事件的 `object3`。

正确成功事件：

```text
action = api_req_success
object3 = ""
```

报表不得期待 `biz_0`，也不得把空 `object3` 当成缺失数据。

## 8. 采样和排除规则

### 8.1 全局配置

全局配置字段：

```text
apiTraceSamplingRate: float，范围 [0, 1]
```

- APP 本地默认值：`0`；
- 服务端当前约定值：`1`；
- 越界值在客户端限制到 `[0,1]`；
- 非法值按 `0` 处理。

### 8.2 采样方式

- 每次 APP 进程启动只生成一次随机数；
- 配置接口成功后，根据 `random < apiTraceSamplingRate` 得到本次启动是否上报；
- 同一次启动内，普通业务接口共用同一个采样开关；
- 不依赖 UID 或 deviceId；
- 被采中的启动上报完整 start/终态链路，未被采中的启动不生成普通接口事件。

### 8.3 特殊接口

| 接口/类型 | 规则 |
| --- | --- |
| `/api/v1/app/config` | 固定上报，不受采样开关影响 |
| `/apix/v1/time` | 固定独立上报，不受采样开关影响 |
| `/apix/v1/app/device/challenge` | 固定独立上报，不受采样开关影响 |
| `/apix/v1/app/device/register` | 固定独立上报，不受采样开关影响 |
| `/api/v1/collect` | 永久排除，尾斜杠形式也排除，避免递归和死循环 |
| 轮询接口 | 不统计，由调用方设置 `tracePolicy=excluded` |
| 其他 `/apix/...` Gateway 接口 | 当前不进入接口监控 |
| `/aitown-chat/...` | 不进入本业务 API trace |
| 其他非 `/api/...` 请求 | 不进入本业务 API trace |

采样开关只控制新事件生成，不影响本地数据库中历史事件继续上传。

### 8.4 报表中的采样注意事项

- 成功率、失败率、耗时分位数可以在随机样本内直接计算；
- 绝对请求量不能简单等同于事件量；
- 当采样率固定时，可用 `样本终态数 / 采样率` 粗略估算普通接口请求量；
- 当采样率随时间变化时，事件当前没有携带当次采样率，不能仅凭事件精确还原绝对请求量；
- 配置接口和三个 Gateway 启动接口固定上报，不能与普通采样接口混在一起做总体请求量估算；
- 建议默认从全局 API 汇总中排除 `/api/v1/app/config`，另设配置接口监控卡片。

## 9. 重试与耗时口径

### 9.1 逻辑请求

一次自动重试链路仍视为一个逻辑请求：

- 一个 `api_req_start`；
- 一个最终终态；
- start 与终态共用同一个 `object2/request_id`；
- 中间失败的 attempt 不产生 `api_req_fail_tech`；
- 最终失败且发生过重试时，`ext_data.retry_count > 0`。

页面或业务层重新调用接口属于新的逻辑请求，应生成新的 request ID 和新的一组事件。

### 9.2 `object4`

- start 固定为 `0`；
- 终态单位为毫秒；
- 自动重试场景只记录最后一次实际 transport send 的耗时；
- 不包含之前失败 attempt 的累计时间；
- 已实际发送业务请求时，不包含发送前的 Gateway 注册、时间同步和签名准备时间；这些耗时由独立 `/apix/...` 接口监控及启动阶段诊断承载；
- 请求发送前失败时，记录 URI、header、body 等准备阶段实际已经消耗的时间。
- ApiClient 从请求头准备起共享总超时预算；预算耗尽仍记 `tech_client_1004`。这不会改变上面的耗时口径：已经开始发送时，以最后一次 transport 已消耗的时间为准，即使取消收尾尚未完成。

因此 `object4` 适合衡量“最终一次接口尝试”的性能，不等同于用户从首次调用到自动重试结束的完整等待时间。

## 10. 事件写入与完整性

- start 与终态独立写入同一个现有埋点数据库/队列；
- 两者不放在同一个数据库事务中；
- start 写入失败不能阻止终态写入；
- 埋点自身异常不能改变业务请求结果；
- 不能强制假设所有 start 都一定有终态，也不能强制假设所有终态都一定能找到 start。

报表主口径应使用终态事件，不应使用 start 数作为请求总数。start 主要用于链路完整性监控。

## 11. 报表建议

### 11.1 基础派生字段

建议在清洗层生成：

| 字段 | 生成规则 |
| --- | --- |
| `endpoint` | `object1` |
| `request_id` | `object2` |
| `duration_ms` | 将终态 `object4` 转为整数 |
| `is_terminal` | action 属于三个终态 action |
| `is_success` | `action = api_req_success` |
| `is_tech_fail` | `action = api_req_fail_tech` |
| `is_app_fail` | `action = api_req_fail_biz` |
| `failure_layer` | `success`、`technical`、`application` |
| `code_family` | `tech_http`、`tech_client`、`biz`、空 |
| `status_or_code` | 从 `object3` 最后一个下划线后的数字解析 |
| `root_cause_group` | 按本文客户端码和 `err_no` 字典映射 |

不要直接按 message 聚合。message 可能变化、被截断或为空。

### 11.2 请求总量

```text
sampled_request_count
  = count(action in [api_req_success, api_req_fail_tech, api_req_fail_biz])
```

不要把 `api_req_start` 加入终态总量，否则会重复计算。

### 11.3 端到端成功率

```text
api_success_rate
  = api_req_success
  / (api_req_success + api_req_fail_tech + api_req_fail_biz)
```

这是用户最终拿到成功结果的比例。

### 11.4 技术失败率

```text
technical_failure_rate
  = api_req_fail_tech
  / all_terminal_requests
```

可继续拆分：

- HTTP 技术失败率：`object3 LIKE 'tech_http_%'`；
- 客户端技术失败率：`object3 LIKE 'tech_client_%'`；
- 网络失败率：客户端码 `1010-1019`；
- 超时率：客户端码 `1001-1004`；
- TLS 失败率：客户端码 `1020-1021`；
- 请求构造失败率：客户端码 `1101-1104`；
- Gateway 失败率：客户端码 `1301-1399`；
- 响应协议失败率：`tech_http_2xx` 且 `ext_data.reason` 为解析/结构问题。

### 11.5 应用层失败率

```text
application_failure_rate
  = api_req_fail_biz
  / all_terminal_requests
```

建议再拆为：

```text
expected_business_failure_rate
server_internal_err_no_rate
auth_or_account_failure_rate
dependency_failure_rate
unclassified_err_no_rate
```

其中服务端质量异常至少包括当前已知：

```text
3101, 3102, 3103, 3104,
4000, 4001, 4002, 4003, 4005,
5000,
10003,
10008
```

`10003` 是否完全归责服务端需要结合客户端版本、Gateway 状态和服务端时间共同判断，但应进入技术关注列表。

### 11.6 接口技术可达率

如果要衡量“接口是否成功返回了合法应用层响应”，可以使用：

```text
application_response_rate
  = (api_req_success + api_req_fail_biz)
  / all_terminal_requests
```

该指标把合法的 `err_no != 0` 视为接口技术可达，但不代表用户操作成功。

### 11.7 应用层业务成功率

```text
application_business_success_rate
  = api_req_success
  / (api_req_success + api_req_fail_biz)
```

该指标排除没有形成合法应用响应的技术失败，适合观察服务端业务结果分布。

### 11.8 服务端质量失败率

建议把 HTTP 服务端错误和应用层内部错误合并为独立质量指标：

```text
server_quality_failure_count
  = tech_http_5xx
  + root_cause_group in (
      server_internal_db,
      server_internal_contract,
      server_internal_system,
      server_dependency
    )
```

分母可根据场景选择全部终态或该接口终态，但报表中必须标明。

### 11.9 耗时

对终态事件的 `object4` 计算：

- 平均耗时；
- P50；
- P90；
- P95；
- P99。

建议分别展示：

- 成功请求耗时；
- 应用层失败耗时；
- HTTP 技术失败耗时；
- 客户端超时和连接失败耗时。

不要把 start 的 `object4=0` 放入耗时分位数。

### 11.10 埋点完整性

start/终态通过 `request_id` 左右关联，可监控：

```text
missing_terminal_rate
  = 超过观察窗口仍没有终态的 start
  / start_count

orphan_terminal_rate
  = 找不到 start 的终态
  / terminal_count
```

这两个指标用于监控埋点写入、APP 被杀进程和队列完整性，不应直接算作 API 技术失败率。

## 12. 推荐报表页面

### 12.1 总览

- 采样终态请求数；
- API 端到端成功率；
- 技术失败率；
- 应用层失败率；
- 应用响应率；
- 服务端质量失败率；
- P50/P90/P95/P99；
- 未知客户端错误 `tech_client_1999` 占比；
- 未归一化服务端错误 `biz_-1` 占比。

### 12.2 接口排行

按 `object1` 展示：

- 请求量；
- 成功率；
- 技术失败率；
- 服务端内部失败率；
- 正常业务失败率；
- P95/P99；
- Top `object3`。

### 12.3 技术失败页

- `tech_http_*` 与 `tech_client_*` 占比；
- HTTP 状态码趋势；
- 客户端技术码趋势；
- 按 APP 版本、系统、网络类型、接口切分；
- `tech_http_200` 的 reason 分布；
- `tech_client_1999` 的精简 message 样本。

### 12.4 应用层失败页

- Top `biz_<err_no>`；
- 按 root cause group 分布；
- 正常业务规则失败与服务端质量异常分开展示；
- `object1 + err_no` 交叉排行；
- 新出现或字典未识别的 `err_no` 告警。

### 12.5 埋点质量页

- start 无终态；
- 终态无 start；
- 同一 request ID 多终态；
- 终态 `object3` 格式不合法；
- `api_req_fail_tech.object3` 为空；
- `object4` 无法解析或为负数；
- `ext_data` 不是空字符串且无法解析为 JSON。

## 13. 数据质量校验规则

建议数据入仓时执行：

1. `api_req_start.object3 == ""`；
2. `api_req_success.object3 == ""`；
3. `api_req_fail_tech.object3` 必须匹配 `^tech_(http|client)_\d+$`；
4. `api_req_fail_biz.object3` 必须匹配 `^biz_-?\d+$`；
5. 每个 request ID 最多一个终态；
6. `object4` 可解析为非负整数；
7. `object1` 以 `/api/` 开头；
8. `object1` 不包含 query；
9. `/api/v1/collect` 不应出现任何四类事件；
10. 轮询接口不应出现四类事件；
11. `ext_data` 非空时必须是 JSON object string；
12. 新版报表不得混入旧 action。

## 14. 维护规则

- 客户端技术码一旦上线不得更改既有含义；
- 新技术类型使用未占用的新码；
- 服务端新增或修改 `err_no` 时同步更新报表字典；
- 不以 `err_msg` 作为稳定业务逻辑或报表主键；
- 对码值冲突或同码多义情况，必须结合接口 `object1` 判断；
- `tech_client_1999` 和 `biz_-1` 应保持低占比，并持续推动归一化；
- 报表 SQL、告警规则和客户端判定顺序必须与本文保持一致。
