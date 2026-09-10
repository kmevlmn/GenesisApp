# AGENTS.md

本文件是 `genesis_app/` Flutter 工程内的项目索引和编码约束。修改本目录下文件时，先按这里的接口文档、业务入口和共享组件边界定位，再做最小可验证改动。

## 产品信息回答边界

- 讨论实际产品逻辑、正式接口字段、线上数据、商品配置、命名规则或用户可见行为时，只依据正式业务代码、接口契约和实际运行链路。
- 不得把 mock、fixture、测试数据、自测配置或测试辅助实现混入产品结论，也不得用它们推断正式商品档位、字段值或命名规则。
- 只有用户明确询问测试实现、mock 或 fixture 时，才讨论这些内容，并清楚标明其测试属性。
- 如果正式代码或接口契约不足以确认答案，直接说明尚不能确认并继续查正式来源，不用测试数据补全答案。

## 项目定位

GenesisApp 是 Flutter App，入口在 `lib/main.dart`。`AppBootstrap.initialize()` 负责初始化 Flutter binding、Firebase、服务注册和 guest bind；`GenesisApp` 使用 `MaterialApp`，默认路由是 `RouteNames.home`，路由表在 `lib/routers/app_router.dart`。

底部主 Tab 由 `lib/pages/app_shell_page.dart` 管理：

- `HomePage`：`lib/pages/home/home_page.dart`
- `OriginPage`：`lib/pages/origin/origin_page.dart`
- `CreateOriginPage`：`lib/pages/create/create_origin_page.dart`
- `MessagesPage`：`lib/pages/messages/messages_page.dart`
- `MePage`：`lib/pages/me/me_page.dart`

## 目录定义

- `lib/app/`：配置、服务注册、依赖注入和 App scope。运行参数集中在 `lib/app/config/app_config.dart`，服务装配在 `lib/app/bootstrap/service_registry.dart`。
- `lib/routers/`：路由名、路由参数兼容解析和页面实例化。新增页面入口时先更新 `RouteNames` 和 `AppRouter.onGenerateRoute`。
- `lib/pages/`：页面级业务逻辑。页面负责拉取/组合数据、导航、刷新、分页和本页面状态。
- `lib/components/`：跨页面 UI 组件。共享样式、弹窗、头像、地图、聊天 UI、讨论列表等应改这里，避免页面局部复制。
- `lib/network/`：HTTP client、Genesis API facade、V1 API resource、chatroom WebSocket/HTTP、mock transport、SQLite 缓存和网络模型。
- `lib/platform/`：设备 ID、session store、Google/Apple 登录、原生图片选择等平台能力。
- `lib/utils/`：图片资源选择、上传图片处理、显示名、相对时间、数字格式化等纯工具。
- `lib/ui/`：主题和基础 UI token。
- `assets/`：静态图片、自定义图标 png/svg/font。
- `docs/`：接口契约、组件说明、跨平台目录和联调记录。
- `test/`：按 `network/components/pages/ui/utils/storage` 分组的 focused tests。

## 运行和配置

常规运行：

```sh
cd /Users/ionix/Works/GenesisApp/genesis_app
flutter pub get
flutter run
```

可用 dart-define：

- `GENESIS_API_ENV=mock|local|debug|real|prod|production|auto`：控制是否使用 `LocalMockGenesisTransport`。
- `GENESIS_CHATROOM_WS_URL=...`：覆盖 WebSocket 地址，默认 `wss://api.worldo.ai/aitown-chat/ws`。
- `GENESIS_CHATROOM_HTTP_URL=...`：覆盖 chatroom HTTP base，默认 `https://api.worldo.ai/`。
- `GENESIS_GATEWAY_API_URL=...`：覆盖 Gateway base，默认 `https://api.worldo.ai/apix/`。Developer page 只配置 host，保存时归一化到 `https://host/apix/`。
- `GENESIS_DEBUG_PROXY=host:port`：HTTP 和 WebSocket 代理调试。
- `GENESIS_DEBUG_WS_LOG=true`：打印 WebSocket frame。
- `GENESIS_ALLOW_IOS_PLATFORM_HEADER=true`：允许 iOS 发送 `x-platform: ios`；默认仍发送 `android`。

外层 `scripts/flutter_run_debug_proxy.sh` 会自动注入真机代理参数。

## 接口文档位置

HTTP 接口以 Apifox 文档为准：

- 主文档：`docs/apifox-http-api-contract.md`
- Gems cent 客户端契约：`docs/gem-cent-app-contract.md`
- Gateway 验签、注册、诊断流程：`docs/gateway-auth.md`
- API facade：`lib/network/genesis_api.dart`
- V1 resource：`lib/network/v1/*.dart`
- 通用 client：`lib/network/api_client.dart`
- 本地 mock：`lib/network/local_mock_genesis_transport.dart`
- 主要测试：`test/network/genesis_api_test.dart`、`test/network/local_mock_genesis_transport_test.dart`

`docs/apifox-http-api-contract.md` 当前覆盖用户、origin、world、chatroom、search、discuss、direct_message、notify、upload。所有 Apifox 200 响应按 `{err_no, err_msg, data}` envelope 处理。改 HTTP 字段时要同步文档、V1 resource、`GenesisApi` 映射、本地 mock 和 focused tests。

Gateway 接入规则：

- 业务 HTTP 仍走 `/api/...`，但 `/api/...`、`/aitown-chat/...` 和 WSS 建联都要按 `docs/gateway-auth.md` 注入 Gateway `X-*` 签名 header。
- Gateway 自身接口走 `/apix/...`；`time/challenge/register/heartbeat/signature/verify` 等诊断和注册接口不要误迁移到 `/api/...`。
- 公共 header 不再发送 `app-platform`、`device-id`、`app-id`、`app-version`；公共 `user-agent` 为系统名 + 系统版本。签名内部的 `X-App-Version` 来自原生包版本，改 `pubspec.yaml` 后必须重新 build/install。

Chatroom WebSocket/HTTP 另有独立契约：

- WebSocket 文档：`docs/chatroom-websocket-api.md`
- WebSocket client：`lib/network/chatroom/chatroom_client.dart`
- WebSocket envelope/model/parser：`lib/network/chatroom/chatroom_models.dart`
- 连接控制：`lib/network/chatroom/chatroom_connection_controller.dart`
- 世界聊天室业务服务：`lib/network/chatroom/world_chatroom_service.dart`
- Chatroom HTTP resource：`lib/network/chatroom/chatroom_http_api.dart`
- Chatroom HTTP models：`lib/network/chatroom/chatroom_http_models.dart`
- 消息本地缓存：`lib/network/chatroom/chatroom_message_storage.dart`
- 主要测试：`test/network/chatroom/chatroom_client_test.dart`、`test/network/chatroom/world_chatroom_service_test.dart`、`test/network/chatroom_http_api_test.dart`

WebSocket 当前协议规则：

- 建联：`GET {GENESIS_CHATROOM_WS_URL}?world_id={world_id}`，`Authorization: Bearer ...` 由 session store 注入，并通过 Gateway handshake signer 增加 `X-*` 签名 header。
- JSON 字段命名使用 `snake_case`。
- 客户端上行 `join/send_message/heartbeat/leave`，上行业务字段在顶层，不包旧版 `payload`。
- `join` 必须带 `world_id`、`location_id`、`user_id`、`sender_id`、`sender_name`。
- 服务端下行公共字段在顶层，个性化内容在 `payload`。
- 错误统一由 `type: "ack"` 携带 `err_no`、`err_msg`，不要恢复旧 `error` 事件。
- `tick_advance` 使用顶层 `current_time` 和 `payload.tick_no`；页面展示只保留连续 tick 的最新可见项时，在页面/聊天 UI 层处理。
- `WorldChatroomService` 负责把世界级事件分发到地点队列；tick 事件需要扇出到所有 leaf location 队列。

## 关键页面业务逻辑

- `HomePage`：首页 feed 和我的 world 卡片入口，默认 App 首屏。列表/卡片展示字段来自 `GenesisApi` 对 v1/home 和 world/origin 数据的映射。
- `OriginPage`：Origin 模板列表和模板卡片入口。卡片组件主要在 `lib/components/origin/origin_item_card.dart` 和 `lib/components/home/popular_origin_list.dart`。
- `OriginWorldPage`：Origin 详情/预览页，不等同于已加入 world。复用 `WorldDetailsPageScaffold`、`WorldDetailsShell`、`WorldMap`、`WorldTickEventItem`；Launch 通过 `showOriginRoleLaunchSheet` 选择角色后创建/进入 world。Origin inline chat 是 launch-only 预览，不应显示真实连接状态。
- `WorldPage`：已创建/加入的 world 详情页。使用同一套 floating map + panel scaffold。进入页面后先拉 world detail，只有 `relation_status` 为 `owner` 或 `joined` 才启动长期 chatroom WebSocket；`approved` 只用于 Launch 流，不代表已连接。
- `LocationChatPage`：地点聊天室页。页面可以从 world drill-down 打开，但只有 leaf location 才允许 `join`/`leave`。非 leaf 只展示页面/地图层级，不产生聊天室副作用。
- `ChatPage`：私信会话页。会话列表和消息缓存由 `DirectMessageConversationStore`、`DirectMessageMessageStore` 以及 `lib/network/direct_message_database.dart` 管理。
- `MessagesPage`：消息中心。负责未读 summary、通知分组、私信入口和 mark-read 刷新；通知列表页是 `MessageCategoryListPage`。
- `DiscussPage`：Origin 讨论列表页，先拉 Origin summary，再通过 `OriginDiscussList` 分页加载顶级评论。发帖入口使用共享 `DiscussPostInput`。
- `PostDetailPage`：单条讨论详情和回复分页。不要把“进入详情”和“直接打开回复 sheet”混在一起；详情页自己负责回复 composer。
- `CreateOriginPage`：创建 Origin 的多步骤 flow。草稿存储在 `CreateOriginDraftStore`，缓存 key 是 `create_origin_draft_v1`；最终 payload 由 draft 转为 `/api/v1/origin/create` 所需结构。
- `EditOriginPage`：编辑已有 Origin。先拉详情并转换成 `MemoryOriginDraftRepository`，复用 origin editor 页和 create flow 外壳，保存走 update 接口。
- `SearchPage`：全局搜索，结果按 origin/world/user 分流，历史记录在 `SearchHistoryStore`。
- `MePage/UserInfoPage/FollowsPage`：当前用户、他人资料、关注/粉丝。Me 优先使用本地 session/cache，避免入口被网络阻塞。
- `SettingsPage/DeveloperPage`：设置和开发维护入口。开发页包含 direct message cache 清理、Gateway host 覆盖、清空 Gateway auth、本地签名诊断等调试功能；Gateway 细节见 `docs/gateway-auth.md`。

## 图片下发、匹配和上传逻辑

图片资源解析的共享入口是 `lib/utils/genesis_image_resource.dart`：

- `GenesisImageResource.fromJson` 支持字符串和 map。
- map 支持 `url`、`image_url`、`image`、`avatar`、`cover`、`sm_url`、`xl_url`、`object_key`。
- `displayUrl` 优先级是 `xl_url -> sm_url -> legacy url`。
- `GenesisImageResourceRegistry` 会用 legacy/sm/xl/object key/display url 建索引；如果后续 UI 只拿到其中一个 key，可以回查完整资源。
- `selectGenesisImageUrl` 有 `xl_url` 和组件逻辑宽度时，会按 `逻辑宽度 * DPR` 匹配 `45/90/180/360/720/1080/2160` 中刚好大于所需宽度的阶梯，并基于清空参数后的 `xl_url` 生成 `?x-oss-process=image/resize,w_{width},image/format,webp`；没有 `xl_url` 或没有宽度信息时回退到旧 display/candidate 兼容逻辑。

HTTP 映射层的图片规则：

- `GenesisApi._resolveImageAssetUrl` 会把后端相对路径经 `resolveAssetUrl` 转成可显示 URL，并注册到 `GenesisImageResourceRegistry`。
- user avatar 主要兼容 `avatar_url` 和 `avatar`。
- origin/world cover、map、snapshot、character avatar、location image 都在 `genesis_api.dart` 的对应 mapper 中解析，修改字段时先查 mapper，不要只改 UI。
- 搜索/讨论等局部 parser 也可能直接使用 `asImageUrl` 或 `GenesisImageResourceRegistry.resolve`，改字段名时要扫调用点。

上传入口：

- 通用 upload API：`lib/network/v1/upload_api.dart`，`POST /api/v1/upload/image`，multipart 字段名是 `file`。
- 创建/编辑 Origin 图片：`CreateUploadBox` 在 `lib/pages/create/create_form_widgets.dart`，先进入 `LocalImageCropPage` 裁剪，再上传。成功后 controller 写入上传 URL，失败恢复旧 URL。
- 讨论图片：`DiscussPostInput` 在 `lib/components/discuss/discuss_post_input.dart`，使用 `native_image_picker.dart` 选图，`resizeImageToMaxWidth` 预处理后上传，最多 6 张并按剩余槽位限制选择。
- 上传进度视觉统一使用 `GenesisUploadProgressOverlay`，不要新增页面局部 spinner。

头像和非头像要分开处理：

- 用户/通用头像共享 `GenesisAvatar`。
- 角色头像共享 `GenesisCharacterAvatar`，带红星角色标识。
- 当前头像默认 top-center crop；不要把头像裁剪规则扩散到 cover、location image、map、list thumbnail 等非头像图片。
- `CharactersList` 和 `OriginWorldPage` 的部分角色肖像有页面级尺寸例外，修改前先确认是否应走共享头像组件。

## 标准页面 Header 标题

- `GenesisBackAppBar` 默认使用 `darkBackground` 背景、`darkTextPrimary` 标题与返回图标及浅色状态栏图标；页面无需重复传入这些默认值，明确的颜色覆盖仍保留。
- 标准返回 Header 统一复用 `GenesisBackAppBar`，`horizontalInset` 默认 16，无需在页面重复传入；返回图标左侧和无操作按钮时标题区域右侧均留 16。自定义右侧操作需将图标或文字的实际右侧留白对齐到 16，计入按钮内部 padding。未登录 Me、Developer 等非标准 Header 不套用此规则。
- Settings、Account、Blocked users、About 的正文左右边距统一为 16，包括列表、空态和底部操作区；法律页使用共享 Header，WebView 内部正文间距由网页样式管理。

- 标准页面 Header 标题统一引用 `GenesisTypography.pageTitle`，通过 `GenesisUiTheme.pageTitleStyle` 使用：字号 20、字重 600、行高 1.4；不得在页面重复硬编码同一字号。
- 标准标题默认左对齐：无返回按钮时沿用左右 16px 页面边距；有返回按钮时与返回图标保持 12px 间距。深浅色只覆盖标题颜色，保留公共排版参数；长标题单行省略，不通过缩小字号适配宽度。
- Home、Inbox、Notifications / Followers / Comments 通知内页、已登录 Me、Profile 和 Follow 页的正文左右边距统一为 16 个逻辑像素；Header 两端的内容或图标区域也对齐到 16。带返回按钮时，返回图标从 x=16 开始，标题保留其后的 12 间距；右侧按钮需计入自身内边距，使图标区域距右边为 16，不能把触摸区外边距与图标留白重复叠加。

## 深色文字 Tab

- 标准下划线文字 Tab 复用 `GenesisTabBar` / `SecendTabs`；选中文字及图标使用 `darkTextPrimary`（95% 白），未选中使用 `darkTextSecondary`（72% 白），下划线使用 `redPrimary`。`GenesisDarkTheme` 提供这些默认值；自定义标签与图标插值同样引用这一对文字 token。
- 本规则适用于文字 Tab，不改变主导航、胶囊选择器、地图专用控件或 Sheet 分页 Handle 的独立规范；Handle 未选中仍用 `darkHandleInactive`（45% 白）。

## 深色卡片表面

- 普通深色信息卡片使用 `GenesisColors.darkCardBackground`（`darkRaisedBackground` 的 80% 不透明度），1px 描边使用 `GenesisColors.darkCardBorder`（6% 白），默认圆角 8px；不添加 Blur。不得在调用处重复写透明度或色值。
- 透明度仅作用于卡片填充，文字继续使用公共文字 token，不对整个卡片加 Opacity。同类卡片在页面与 Sheet 中使用同一套 token，最终底色随容器背景合成。
- 选中、促销等有明确语义的卡片保留对应强调色；输入框、图标圆底和加载骨架继续使用各自的规范，不因卡片表面调整而替换 `darkFaintFill`。

## 公共浮层底色

- 公共操作弹窗和 Creating / Publishing / Progressing 等生成等待浮层统一使用 `GenesisColors.darkOverlayBackground`：`darkRaisedBackground` 的 40% 不透明度，背景模糊使用 `GenesisBlur.strong`（14），仅作用于面板圆角内。不得在组件中重复写透明度。文字保持各自 token 的不透明度；外围遮罩单独管理。普通 Sheet、浮动菜单与 Toast 不使用此半透明底色。

## 公共操作弹窗

- `GenesisActionBox` 统一使用深色样式，包括从浅色页面打开的情况；主题仅作用于弹窗，不能改变调用页面的主题。
- 主面板与独立 Cancel 面板均使用 `GenesisColors.darkOverlayBackground`（由 `darkRaisedBackground` 派生的 40% 不透明度），叠加局限于面板圆角内的背景模糊（`sigmaX / sigmaY = GenesisBlur.strong`（14））；外边框为 1px `darkFaintFill`（约 12% 白），分隔线同样使用 `darkFaintFill`。这些参数在公共组件中集中管理，不在页面重复配置；透明度只作用于面板填充，不给整个弹窗或文字增加 Opacity。
- 标题与普通操作使用 `darkTextPrimary`，说明正文使用 `darkTextSecondary`，UID / WID / 时间等辅助信息和禁用操作使用 `darkTextTertiary`。
- 公共弹窗的红色操作文字使用 `GenesisColors.redSecondary`；主要操作默认继承公共组件颜色，调用处不重复覆盖。Cancel、Reject 等普通操作使用一级白字；红色强调正文同样使用 `redSecondary`。
- 自定义标题、正文和输入框也须引用公共 token；输入文字和光标使用 `darkTextPrimary`，Placeholder 使用 `darkInputPlaceholder`，输入填充使用 `darkFaintFill`，不额外描边。保留各交互所需的输入行数和布局。
- 保留公共弹窗的尺寸、圆角和交互；Report / 消息长按浮动菜单仍按浮动菜单专项规范执行。

## 全局字体规则

- 应用文字统一使用 `GenesisTypography.fontFamily`（Inter）及 `fontFamilyFallback`；中文等 Inter 不含的字形按公共 fallback 显示，图标字体和操作系统原生界面不属于应用文字字体。
- 普通 `Text` / `Text.rich` 可继承全局主题，不能仅凭局部 `TextStyle` 未写 `fontFamily` 判定遗漏。局部深色主题应保留原主题字体。App builder 在页面 Material 外的装饰和根 Overlay 也必须有公共 `DefaultTextStyle`。
- 原始 `RichText`、独立 `TextPainter`、替换式 `DefaultTextStyle` 和 `inherit: false` 样式不保证继承页面字体，必须显式引用公共字体或通过 `GenesisTypography.withFallback` 补齐。手动测量和实际显示必须使用同一套字体，避免宽度、截断和基线不一致。
- `ButtonStyle.textStyle` / `styleFrom(textStyle: ...)` 会替换按钮的主题文字样式，不能按普通 Text 的合并规则处理；自定义按钮文字样式必须包含公共字体。公共主次按钮通过 `GenesisPrimaryButton.defaultTextStyle` 集中管理。
- 不在页面添加分平台系统字体或独立的 `monospace`；新增字体例外必须在本规范写明用途。斜体继续遵守下一节。

## iOS 字体倾斜规则

- 用户可见的斜体统一使用 `GenesisSoftItalicText`，或在富文本场景使用同一文件提供的 `genesisSoftItalicStyle` 与 `genesisSoftItalicForPlatform`；当前 iOS 和非 iOS 默认都使用内置的 Inter Italic 字形。
- 旧版 iOS 正常字形加 `GenesisTypography.iosInlineEmphasisSkew` 的轻倾斜实现必须保留，通过 `GenesisTypography.useIosSoftItalicSkew` 集中控制；当前默认值为 `false`，以后需要恢复时只改该开关，不在 caller 增加局部 Transform。
- 页面和共享组件不得直接为用户可见文字设置 `FontStyle.italic`，Markdown 的 `*emphasis*` 继续复用 `_InlineMarkdownText`/统一斜体链路。
- 修改斜体展示时，测试必须断言 iOS 和非 iOS 的默认 Inter Italic，并保留旧版 iOS 轻倾斜代码路径的可恢复性测试。

## 滚动与边界反馈规范

- App 根节点必须使用 `GenesisScrollBehavior`，全局禁用 Material overscroll indicator。Android 上滚动到首尾时，不得出现内容被拉长、拉宽或缩放变形的 stretch overscroll 效果。
- 不得在页面或共享组件中重新引入 `StretchingOverscrollIndicator`，也不得通过局部 `ScrollConfiguration` 恢复 overscroll decoration。新增独立 `MaterialApp` 运行入口时，同样必须配置 `GenesisScrollBehavior`。
- 允许按交互需要使用 `BouncingScrollPhysics` 实现 iOS 风格的整体内容位移回弹，或使用自定义 physics 实现明确的边缘手势；这种整体位移不等同于禁止的内容拉伸变形。
- 页面可以继续使用 `ClampingScrollPhysics`、`PageScrollPhysics`、`AlwaysScrollableScrollPhysics` 和下拉刷新。不要为了关闭拉伸效果而破坏横向分页、纵向滚动、RefreshIndicator 或既有边缘手势。

## 深色界面颜色规范

颜色统一定义在 `lib/ui/tokens/genesis_colors.dart` 的 `GenesisColors` 中。以下五个 token 是对应标准颜色的唯一色值来源：

| 用途 | Token | 精确值 |
| --- | --- | --- |
| 基础背景：页面、World Sheet、导航栏、地图外围 | `GenesisColors.darkBackground` | `#151517` / `Color(0xFF151517)` |
| 抬升背景：普通 Sheet、浮层、分组容器、部分卡片 | `GenesisColors.darkRaisedBackground` | `#181C1F` / `Color(0xFF181C1F)` |
| 一级文字：主标题、主要内容、高强调文字 | `GenesisColors.darkTextPrimary` | 95% 白 / `Color(0xF2FFFFFF)` |
| 二级文字：次级文字、分组标题、未选中状态 | `GenesisColors.darkTextSecondary` | 72% 白 / `Color(0xB8FFFFFF)` |
| 三级文字：辅助信息、元数据、弱提示 | `GenesisColors.darkTextTertiary` | 45% 白 / `Color(0x73FFFFFF)` |

- 所有百分比均指不透明度。使用处必须引用对应 token，不得重复写上述色值或建立独立的同色常量。
- 页面或组件已有的语义别名可以保留，但必须引用上述 token。例如 Worldo Detail 和 Discuss 的颜色别名只做映射，不再自行定义色值。
- 现有代码的 token 迁移只替换与上述标准颜色对应的色值写法，不改变视觉颜色；其他颜色或不同透明度保持原样，不因数值接近而强行归入这五个 token。
- `GenesisColors.darkInputPlaceholder` 独立定义为 32% 白（`0x52FFFFFF`），不与 45% 白的 `darkTextTertiary` 共用色值；深色光标引用 `darkTextPrimary`。后续调整占位文字只修改公共 placeholder token。
- 需要透明度变体时，从对应 token 派生，若已有对应语义 token（如 `darkCardBackground`），直接引用该 token；不得用变体替代规定的三级文字颜色。
- 不创建肉眼接近的背景色或文字透明度。纯白 `#FFFFFF` 不作为深色内容区常规文字颜色，除非设计明确要求更高强调层级；输入区域和浮动操作菜单按后文专项规范执行。

- 深色页面的命名路由和直接 `Navigator.push` 统一使用 `GenesisDarkPageRoute<T>`（`lib/ui/navigation/genesis_dark_page_route.dart`）。它为 Android 进入、退出和被覆盖时的转场显式提供 `darkBackground`，避免转场读取页面局部 Theme 之外的浅色背景；保留平台返回手势及路由结果类型。

## 原生启动页

- 启动页固定深色，不随系统深浅色切换。原生启动窗口与 Flutter 首帧之前的背景均对应 `GenesisColors.darkBackground`，状态栏使用浅色图标。
- 启动图使用 `assets/images/app_icon.png`，居中显示为 96×96、圆角 12；通过 `dart run tool/generate_launch_assets.dart` 生成 iOS / Android 资源，并从公共背景 token 同步原生色值。修改源图或 token 后须重新生成。
- Android 仅按启动机制保留 Android 12 的版本资源，不复制日间 / 夜间样式。原生启动资源修改后需重新 build / install，热重载不会更新。

## 红色层级规范

红色按用途划分为三个等级，唯一色值定义在 `GenesisColors`；这些是不同色值，不是透明度变体。

| 等级 | Token | 色值 | 用途 |
| --- | --- | --- | --- |
| 一级：品牌红 | `GenesisColors.redPrimary` | `#FF2442` | 主要操作、可用发送按钮、选中态、红点及角色边框等强强调 |
| 二级：正文粉红 | `GenesisColors.redSecondary` | `#FF8A9A` | 深色页面 Personality / 性格描述、事件线索等需要持续阅读的强调正文；取自 Worldo Detail 的 Personality |
| 三级：浅粉色 | `GenesisColors.redTertiary` | `#FFB8C3` | 浅粉填充、轻量装饰；不替代正文或白字层级 |

- 深色页面的红色强调正文必须使用 `redSecondary`，不得使用品牌红 `redPrimary`，避免长段文字过于刺眼。错误提示、危险操作等语义状态单独按其用途处理。
- `brand` / `brandBright` / `create` / `danger` 保留为一级红的语义别名，`brandSoft` 保留为三级红的别名；不再分别定义同色值。
- Worldo Detail Personality、World Detail Cast 的 Personality、Location Chat 的同色强调和 Tick Event 线索统一引用 `redSecondary`。页面级颜色别名可以保留，但必须映射公共 token。
- 新增及修改红色样式时必须调用对应 token，不复制色值；其他红色、不同透明度和特殊状态不因颜色接近而强行替换。

## 深色主按钮禁用态规范

- Save / Create / Launch / Publish / Select 等标准主操作按钮统一使用 `GenesisPrimaryButton` 的深色默认禁用样式：底色 `GenesisColors.darkButtonDisabledBackground`（由 `redPrimary` 派生的 40% 不透明度品牌红），文字和加载指示器使用 `GenesisColors.darkButtonDisabledForeground`（将 `darkTextSecondary` 预先合成到 `darkBackground` 上的不透明浅灰，保留接近二级白的亮度，避免红色底透入文字）。色值在 `GenesisColors` 集中定义，页面不要重复配置同一套禁用色或透明度。
- 这组 token 适用于深色填充主操作按钮；文字按钮、关闭/删除等图标按钮及中性操作按钮按各自组件规范处理，不因禁用而统一改成红底。
- 禁用及保存进行中不再使用 `redSecondary` / `redTertiary` 等粉色填充；可用态保留品牌红 `redPrimary` 和一级白字。保留现有按钮尺寸、圆角和布局，不新增描边。
- 颜色不改变校验和点击行为：禁用时不得执行主操作，已有 `onDisabledPressed` 说明提示保持；保存进行中沿用现有进度文字或加载指示器。

## 深色面板关闭按钮规范

- 普通深色 Sheet、弹层和面板的关闭按钮统一使用 `GenesisDarkCloseButton`（`lib/ui/components/genesis_dark_close_button.dart`），调用方只传 `onPressed` 和可选 `key`，不得重复拼装圆底与关闭图标。
- 按钮为 28×28 的圆形，填充使用 `GenesisColors.darkFaintFill`（约 12% 白）；内部 `Icons.close_rounded` 图标为 17px，使用 `GenesisColors.darkTextPrimary`。禁用时保留圆底，图标使用 `darkTextTertiary`，不响应点击；公共组件提供 `Close` 提示。
- 尺寸和状态样式由组件集中管理。外部定位、Header 边距及关闭回调仍由调用方负责，不因复用而改变页面关闭行为。
- `GenesisBottomSheetCloseButton` 在深色主题下转用此组件；`GenesisBottomSheetPanel` 的深色面板与安全区使用 `darkRaisedBackground`，默认标题使用 `darkTextPrimary`。浅色调用沿用原样式。
- 图片查看器、裁剪工具的专用工具栏关闭操作，以及搜索清空、附件删除，不属于普通面板关闭按钮，保留各自的布局和交互规格。

## 公共删除按钮规范

- 图片预览、头像上传及编辑卡片中的图标删除按钮统一使用 `GenesisDeleteButton`（`lib/ui/components/genesis_delete_button.dart`），不在页面重复拼装样式。
- 默认按钮 24×24、删除 SVG 14px、圆角 6px；不透明底色使用 `GenesisColors.darkFaintSurface`（`#313133`），1px 描边使用 `darkFaintFill`，图标使用 `darkTextPrimary`。不叠加背景模糊。
- 禁用时整体不透明度为 45%，禁止执行删除；可以通过 `onDisabledPressed` 提示不可删除的原因。按钮位置、删除回调和确认流程由调用方负责。
- 本规范用于独立图标按钮；Report 菜单内的 Delete 文字操作继续遵守浮动菜单规范。

## 数字角标规范

- 未读及地图事件数字角标统一由 `GenesisCountBadge`（`lib/ui/components/genesis_count_badge.dart`）绘制，不在页面重复实现数字排版。
- `GenesisUnreadBadge` 管理未读数小于等于 0 时隐藏，默认高度 16、字号 10、字重 600；`WorldEventCountBadge` 保留地图紧凑规格：高度 14、字号 9.5、字重 800。
- 单位数为等宽高圆形，多位数按内容扩展为胶囊，左右 padding 4；超过 99 显示 `99+`。底色引用 `GenesisColors.redPrimary`，数字使用纯白、显式 Inter 及公共 fallback、行高 1，水平和垂直居中；不继承页面文字样式，不添加分平台的文字位移补偿。
- 角标相对图标或头像的外部定位仍由调用方管理，不将定位偏移应用到内部数字。

## 深色 Toast 设计规范

- 页面短提示统一使用 `showGenesisToast` / `showGenesisToastInOverlay`，实现位于 `lib/components/common/genesis_center_toast.dart`，不得在页面自行拼装或用 `SnackBar` 替代。
- 底色固定为不透明 `#424244`，唯一色值来源为 `GenesisColors.darkToastBackground`；使用处引用 token，不重复硬编码。不使用半透明白底、深灰旧色 `#383B42` 或额外背景 blur。
- 文字为纯白 `Colors.white`，这是 Toast 的明确高对比文字例外；字号 14、字重 `FontWeight.w400`、行高 1.4，沿用 `GenesisTypography` 字体及 fallback，居中排版。
- 外形为胶囊圆角，使用 `BorderRadius.circular(999)`；不加描边或阴影。内边距左右 16、上下 8，单行默认高度约 36；长文案允许换行并自然增高，不固定高度截断文字。
- Toast 在根 Overlay 中水平、垂直居中，屏幕左右至少留 36；不改为底部系统提示的位置。以上尺寸均为 Flutter 逻辑像素。
- 默认显示 2 秒，可由调用方通过 `duration` 指定；新提示替换旧提示，不堆叠；提示不拦截底层触摸，空白文案不展示。
- 深色样式依据触发页面主题或显式 `brightness: Brightness.dark`，不能受根 Overlay 的浅色主题影响。本节只规定深色 Toast，浅色分支独立保留。
- 系统剪贴板提示由操作系统管理，不属于此组件；不以系统提示的存在或样式替代应用 Toast 的规范。

## 深色 Sheet Handle 设计规范

- 顶部横向分页 Handle 的颜色以 Worldo Sheet 为基准：选中段使用 `GenesisColors.darkHandleActive`（`darkTextPrimary`，95% 白），未选中段使用 `GenesisColors.darkHandleInactive`（`darkTextTertiary`，45% 白）。不得用输入填充的 12% 白代替未选中颜色。
- 两个 Handle token 是公共文字颜色的语义别名，不另定义色值；所有同类深色分页 Handle 统一引用这两个 token。
- 滑动过程中，根据页面进度对选中／未选中颜色和段宽连续插值，保持圆角；不增加闪烁、呼吸或循环动画。
- 颜色标准与分页数量、尺寸分开管理；段宽和间距按分页数量设计，统一颜色时不改变手势、触摸区域或页面布局。
- 单一、无选中态的深色 Sheet 拖动条默认使用 `darkHandleInactive`；需要表达当前分页选中态时才使用 `darkHandleActive`。

## 深色输入框与 Placeholder 设计规范

适用于 Location Chat 的 Message 输入框、Worldo Detail / Discuss 的 Write a post 入口，以及 Post Detail 的 Write a reply 入口。新增或修改同类深色输入场景时，按以下标准实现；所有尺寸均为 Flutter 逻辑像素，百分比均指不透明度。

| 属性 | 标准 |
| --- | --- |
| 填充色 | 约 12% 白，精确值 `Color(0x1FFFFFFF)`；复用 `GenesisColors.darkFaintFill` |
| 基础背景 | `GenesisColors.darkBackground`（`#151517`）；透明填充的最终显示色随底层内容变化 |
| 最小高度 | 40，指单行输入区域，不包含外部安全区、工具栏或快捷操作区 |
| 圆角 | 8 |
| 左右内边距 | 14 |
| 上下内边距 | 10 |
| 字号 / 行高 | 14 / 1.4 |
| 字重 / 字间距 | `FontWeight.w400` / 0；沿用项目字体体系 |
| 对齐 | 左对齐；单行占位文字在输入区域内垂直居中 |
| 输入正文 | `GenesisColors.darkTextPrimary`，95% 白 |
| Placeholder | 32% 白 `Color(0x52FFFFFF)`；统一复用 `GenesisColors.darkInputPlaceholder` |
| 光标 | `GenesisColors.darkTextPrimary`，95% 白；可复用同色的正文样式 |
| 边框 | 输入区域本身不额外添加描边、下划线或 Material 默认边框 |

实现约束：

- Placeholder 必须显式使用上述 32% 白 token，不得继承全局浅色 `textDisabled` 或使用普通三级文字色；提示引导文案保持 `darkTextTertiary`（45% 白）。真实输入框通过 `hintStyle` 设置；点击打开编辑器的入口通过占位 `Text` 的样式设置。
- 光标不得使用纯白或品牌红。品牌红用于发送等可用操作，不用于 placeholder 或输入光标。
- 40 是最小高度，不是固定高度；保留实际输入框随多行文字增长的行为。底部入口与打开后的发帖/回复编辑弹层是不同组件，不能把弹层的 3–6 行编辑区压缩成 40 高。
- blur 与填充色分别管理：Location Chat 输入背景保留现有 blur 4；Worldo Detail / Discuss 入口不为追求颜色一致而新增 blur。不能用改变填充透明度来补偿 blur 差异。
- 不改全局浅色输入主题来实现局部深色样式。优先复用共享 token 和组件；聊天 placeholder 通过 `ChatUiStyleConfig.inputHintStyle` 传递，Worldo Detail 通过 `originWorldDetailSheetFaintPlaceholderColor` 引用共享 token。
- 参考实现：`lib/components/chat/shared/chat_ui_library.dart` 的 `kLocationChatStyle`、`chat_ui_composer.dart` 的 `ChatComposer`、`lib/components/discuss/discuss_post_facade.dart` 的 `DiscussPostInput`，以及 `lib/pages/discuss/post_detail_page.dart` 的 `_PostDetailCommentBar`。

## 关联背景与浮动操作菜单规范

- Discuss 缩进回复底色与输入入口复用 `GenesisColors.darkFaintFill`（约 12% 白）。
- Discuss 发帖/回复弹层、附件删除按钮和刷新指示器需要不透明背景时，使用同一填充叠在 `#151517` 上的合成色 `GenesisColors.darkFaintSurface`（`#313133`），避免透出后方内容。
- Report 等浮动操作菜单与 Message 长按菜单保持一致：背景固定 `#666666`，文字和图标为白色。深色页面也沿用该灰色菜单，不使用页面/Sheet 的 `#181C1F` 或输入区域底色替代。菜单触发按钮的颜色可按所在页面配置。

## 刷新与加载指示器规范

- 下拉刷新统一使用 `GenesisRefreshIndicator`（`lib/ui/components/genesis_refresh_indicator.dart`），不得在页面内重复配置标准刷新颜色。
- 深色刷新圆环使用 `GenesisColors.darkTextSecondary`，底色使用 `GenesisColors.darkRaisedBackground`；浅色沿用主题圆环颜色和页面背景。已有明确视觉例外通过 `color` / `backgroundColor` 参数传入。
- 列表初次加载、重新加载等独立圆环使用同文件的 `GenesisLoadingIndicator`，与下拉刷新共用深浅色前景规则；尺寸和线宽按当前布局保留。
- 组件只管理指示器表现。刷新回调、滚动控制器、嵌套滚动通知筛选和手势逻辑仍由调用方维护，不因样式封装改变刷新时机或产生重复请求。
- 内容骨架继续遵守下方静态骨架规范，不用旋转圆环替换已约定的骨架布局。

## 加载骨架样式规范

- 深色页面和 Sheet 的加载骨架统一采用 Worldo Sheet 的静态色块样式：填充色为约 12% 白，精确使用 `Color(0x1FFFFFFF)`。该透明度用于占位色块，不属于文字透明度层级。
- 普通条形骨架默认圆角为 4 个逻辑像素；头像、封面等占位按对应内容的形状和圆角展示。宽高、行数和间距根据待加载内容布局设置。
- 骨架保持静止、纯色填充；禁止渐变扫光、shimmer、闪烁、呼吸透明度及循环动画，不为骨架创建重复运行的 `AnimationController` 或定时器。
- 骨架沿用所在页面或 Sheet 的背景，不额外铺设浅色底。数据到达后替换为实际内容。
- 参考实现：`lib/pages/origin/origin_world_map_shell.dart` 的 `_OriginLoadingBone`，以及 `lib/pages/discuss/discuss_page.dart` 的 `_DiscussSkeletonBone`。

## 共享组件边界

- 通用底部弹层：`GenesisBottomSheetPanel`
- 通用确认/操作框：`genesis_action_box.dart`
- 居中 toast：`showGenesisToast`，不要用 `SnackBar` 替代项目内短提示。
- 聊天 UI token 和结构：`lib/components/chat/shared/chat_ui.dart`、`chat_ui_style_config.dart`
- 世界/Origin floating panel：`WorldDetailsPageScaffold`、`WorldDetailsShell`
- 世界地图和点位：`WorldMap`、`WorldMapStage`、`WorldPoint`
- Discuss 列表/回复/输入：`OriginDiscussList`、`OriginDiscussRepliesList`、`DiscussPostInput`
- 图片查看器：`GenesisImageViewerOverlay`

如果多个页面使用同一个组件，优先改共享组件并检查所有 call site；只有明确是页面例外时才加 caller override。

## 名称展示规则

- Origin（即 Worldo）name 在所有展示位置前加 `#`；使用 `originDisplayName`，避免重复添加。
- World name 在所有展示位置都不加 `#`；直接展示原始 world name（为空时可回退 WID）。

## 验证要求

按改动范围选择最小能证明正确性的验证：

- Android production arm64 release APK 使用 `flutter build apk --release --flavor production --target-platform android-arm64`；禁止使用 `--split-per-abi`，否则 Flutter 会改写 APK 的 `versionCode`。
- 格式：`dart format <touched files>`
- 静态检查：`flutter analyze` 或文件相关 analyze
- HTTP/API：`flutter test test/network/genesis_api_test.dart`、`flutter test test/network/local_mock_genesis_transport_test.dart`
- Gateway：`flutter test test/network/gateway_auth_test.dart`
- Chatroom：`flutter test test/network/chatroom/chatroom_client_test.dart`、`flutter test test/network/chatroom/world_chatroom_service_test.dart`、`flutter test test/network/chatroom_http_api_test.dart`
- Discuss：`flutter test test/components/discuss_page_test.dart`、`flutter test test/components/origin_discuss_list_test.dart`
- 图片/头像：`flutter test test/utils/image_upload_processing_test.dart`、`flutter test test/ui/genesis_avatar_test.dart`、`flutter test test/ui/genesis_list_image_test.dart`
- 页面流：优先使用 `test/widget_test.dart --plain-name "<case name>"` 跑相关窄用例，不要默认只跑全量大烟测。

完成前报告实际跑过的命令；不能运行时说明原因和剩余风险。

## 背景模糊规范

背景毛玻璃统一引用 `lib/ui/tokens/genesis_blur.dart`：`GenesisBlur.light` 为 4，`GenesisBlur.strong` 为 14；0 表示关闭。开发设置也使用这三档。阴影和地图加载动画的光晕不属于背景模糊。
