# 深色模式遗漏检查

检查日期：2026-09-10（公共 Header 默认深色修改后复查）。范围：当前工作区 Flutter 命名路由、直接打开的页面、Sheet / Dialog 入口、共享组件调用链及加载/错误分支。
本次为代码检查，没有逐页运行截图；下文的确定项依据实际调用链和显式颜色，转场闪白仅列为风险，未声称设备上复现。没有修改页面样式。

## 整页尚未适配

| 页面 | 当前实现 | 代码位置 |
| --- | --- | --- |
| 私信 Chat | 会话背景 #EDEDED，浅色 Header / Composer，白色输入框，白色对方气泡、黑色正文，自身气泡绿色 | `lib/pages/chat/chat_page.dart:609`；`lib/components/chat/shared/chat_ui_library.dart:133`；`lib/components/chat/shared/chat_ui_style_config.dart:202` |
| Buy Gems | 白色 Scaffold、白色商品卡、浅灰任务及说明区域、深色正文；Header 已继承深色默认，但 Records 仍为 #333333 且显式使用旧状态栏样式 | `lib/pages/gems/gem_wallet_page.dart:182`；`gem_wallet_content.dart`；`gem_wallet_state_panels.dart`；`lib/components/gems/gem_purchase_catalog.dart` |
| Gem Records | Header 已继承深色默认；页面仍白底，Tab、记录正文和空态仍为浅色页文字体系 | `lib/pages/gems/gem_records_page.dart:180` |

## Sheet / 弹窗遗漏

| 入口 | 当前实现 | 代码位置 |
| --- | --- | --- |
| Gems 不足 → 充值 Sheet | 无显式深色主题包装，底板受调用处主题影响；内部商品卡固定白色、说明卡 #F7F7F7、浅色边框与深色文字。即使从深色页面打开，也存在白卡片 | `lib/components/gems/gem_balance_prompt.dart:41`；`lib/components/gems/gem_purchase_bottom_sheet.dart:50`、`:299`、`:366`；`lib/components/gems/gem_purchase_catalog.dart:196` |

## 已处理的分支遗漏（2026-09-10）

1. **Worldo 首次加载失败：已修复。** 错误页显式使用 `GenesisColors.darkBackground`，错误文字使用 `darkTextSecondary`，保留 Retry 行为。
2. **Worldo Detail → Launch Preview：已按要求删除。** 移除入口、组件、专用预览数据处理和样式，不影响 Opening 预览或 World Events。

3. **Setup Your Role：已适配。** Sheet 使用 raised 背景；Preset / Custom 使用深色样式，Playing Tab 及专用状态、加载器、Enter 分支已删除；Launch 为纯文字按钮。

## 全局默认与转场风险

- 根 App 仍为 `GenesisTheme.light()`：`lib/app/genesis_app.dart:31`。全局 ColorScheme 是 Brightness.light，Scaffold 默认 GenesisColors.surface（白色）：`lib/ui/theme/genesis_theme.dart:34`、`:50`。
- 当前深色主要依赖局部 GenesisDarkTheme、DiscussDarkTheme 或组件显式颜色；公共 Header 默认已改深；公共 Sheet、CreateFormTheme 等仍保留浅色默认/分支。不能据正常页面深色就认定所有默认组件已经深色。
- Notifications / New followers / Comments、Profile、Follows 等页面内容已深色，但命名路由仍是 MaterialPageRoute。Home / Worldo / Inbox / Me 的 shell 别名也使用 MaterialPageRoute。Android 默认转场可能读取路由外层浅色主题，需要统一转场或完成全局主题迁移后真机验证；本次没有复现闪白。
- Settings / Account / Blocked users / About、Search、Discuss / Post Detail、Create / Edit、Legal 已有对应 GenesisDarkPageRoute 入口。World / Worldo / Location Chat 有专门转场，需保留各自导航、返回手势及地图到聊天的布局约束。

## Developer 范围

DeveloperPage、DeveloperPageSheet 及其信息、测试开关、测试按钮及 HTTP / WebSocket 等内容仍有浅色卡片、深色文字和浅灰按钮。HTTP / WebSocket 的展开详情、WebSocket 类型筛选 Sheet 与调试解锁弹窗也应归入开发工具单独处理，不与普通用户主路径混算。见 `lib/pages/me/developer_page.dart:112`、`:143`、`developer_components.dart`、`developer_network_tab.dart`、`developer_websocket_tab.dart`、`lib/app/debug_floating_button_unlock.dart:69`。

## 本次核对已有深色实现的范围

- Home、Worldo 列表、Me 已登录/未登录、Profile、Followers / Following、Inbox 和三个通知列表。
- Search、Discuss、Post Detail，以及发帖/回复弹层。
- Settings、Account、Blocked users、About 和 Legal 的 App 外框及网页深色覆盖。
- Create / Edit 首页，Basics、Characters、Locations、Opening、Story Events；L3 编辑 Sheet、角色选择 Sheet、Opening 的 Select Location Sheet。
- World 正常页面及 Detail / Locations / Events / Status 四个 Sheet；Worldo 正常页面与详情主要内容，其中错误态现已修复，Launch Preview 模块已删除。
- Location Chat；Location Chat / Worldo 共用的 @ 提及 Sheet 明确使用 darkRaisedBackground。
- 登录 Sheet、公共 GenesisActionBox、Feedback / Report、编辑昵称、申请处理弹窗。
- 支付处理中/成功、签到/领奖弹窗已使用深色 GenesisActionBox 和深色文字；不要与充值商品 Sheet 混淆。
- Create / Publish / World Tick 进行中的 GenesisGenerationWaitOverlay 调用处明确传入 Brightness.dark；它与旧 WorldTick1WaitDialog 是不同实现。

## 不作为当前页面遗漏的项目

- 图片浏览、裁剪页的黑色背景及图片上的白色工具图标是媒体场景，不算尚未适配的白页面。
- Report / 消息长按菜单 #666666 是已确认的设计规范；品牌 Logo、商品/地图素材、Worldo 卡片的既定设计不因含浅色像素而判为遗漏。
- `CharactersList`、`WorldMapStage`、`OriginDiscussPreviewList`、`confirmCreateFormDelete` 等存在浅色旧实现，但当前生产 lib 中没有对应调用入口；不计入实际可见页面清单。
- `OriginDiscussRepliesList` 的旧浅色回复卡当前不用于新版 Discuss / Post Detail。现用 Worldo 摘要列表设置 showReplies:false，旧 PreviewList 没有生产调用，不能误报为当前 Discuss 回复底色。
- 共享骨架、图片占位以及 CreateFormTheme 中保留浅色分支不等于当前深色调用会显示浅色；本次按调用处主题及覆盖参数判定。
- 系统相册、Google / Apple 登录和支付系统 UI 不由 Flutter 页面 token 直接控制，本次未检查其运行时界面。

## 后续建议顺序

1. Buy Gems / Gem Records / 充值 Sheet 作为一组处理。
2. 私信页面及 Composer / 气泡。
3. Creating Developer 预览与正式生成浮层样式对齐。
4. 最后统一全局默认和转场，再逐入口进行真机或模拟器视觉验收；Developer 单独安排。

## 本次已完成

- Model：深色页面与卡片，品牌红选中描边和白色对勾；Save 使用公共填充主按钮。
- Page not found：深色页面、Header 和路由转场。
- 强制升级：深色页面；Developer 提供固定预览入口，预览允许返回，正式拦截保持不可返回。

## 本轮额外确认的局部遗漏

- Buy Gems 的 Header 因共享默认值已深色，但右侧 Records 仍为 `#333333`，状态栏还传 `kGenesisDefaultSystemUiOverlayStyle`，深底上的可读性需修正（`gem_wallet_page.dart:183`）。
- Profile 的 Header 显式传 `darkTextSecondary`。共享 Header 现在把 foreground 用于标题，折叠后显示的用户名标题和返回箭头均为二级白，与默认一级白规格不一致（`user_info_page.dart:510`）。这是文字层级问题，不是未做深色。
- Worldo 的 Edit Worldo 和 World Detail 的 Invite 仍硬编码品牌红、纯白字及旧 62% 红禁用底（`origin_world_detail_sheet.dart:2040`、`world_sections_loading_detail.dart:307`）。目前两处 onPressed 均非空，不能把该旧禁用配置报告成用户现在可见的禁用状态；属于 token/规范清理。
- `WorldDetailsShell` 仍有白底，但只被无生产调用的 `WorldDetailsPanel` 引用，未计入当前可见页面。World Events 当前明确传 `useChatEventStyle: true`，不能把 WorldTickEventItem 的旧浅色分支误报为 Events 页面。
- Model、Page not found、强制升级页均已显式深色 Header；公共 Header 默认也已深色。Developer 升级预览入口按该页当前浅色样式使用浅灰底黑字。

## 本轮更正与处理

- 首 Tick 旧弹窗：存在受 `waitForTick1` 控制的残留入口，但当前 lib 中无业务调用传 true，默认 false。不再列为当前业务必经的可见遗漏；仅外部显式传路由参数可能触发。
- Creating：Create / Edit 正式调用已传 Brightness.dark 并使用 App icon；Developer 预览未传 brightness，仍显示白色与旧 GenesisLogo。需对齐预览，并考虑统一生成浮层面板样式；本轮只提出方案。
- Buy Gems / Gem Records Header 已显式恢复白底黑字，支付页面按用户要求待合并代码后统一适配。
- Profile Header 已移除局部背景、二级前景及布局覆盖，使用公共默认值。
- Edit Worldo / Invite 按钮已引用 redPrimary、darkTextPrimary 和公共禁用 token。
- 全局 GenesisTheme.light 暂不修改，以保留未迁移页面的浅色外观。

## Creating / Publishing 浮层已统一

正式创建、发布及 Developer Creating 预览统一使用 OriginGenerationWaitOverlay，复用 Progressing 深色面板、固定说明和角色头像轮播；无头像回退 App icon。已删除滚动字幕组件和专用动画。Developer 从列表读取一个 Worldo 的详情作为预览数据，失败时提示并显示默认预览，不发起创建或发布请求。
