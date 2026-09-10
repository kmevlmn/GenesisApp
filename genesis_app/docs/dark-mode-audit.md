# 深色模式遗漏检查

检查日期：2026-09-10。范围：当前工作区 Flutter 命名路由、直接打开的页面、Sheet / Dialog 入口、共享组件调用链及加载/错误分支。
本次为代码检查，没有逐页运行截图；下文的确定项依据实际调用链和显式颜色，转场闪白仅列为风险，未声称设备上复现。没有修改页面样式。

## 整页尚未适配

| 页面 | 当前实现 | 代码位置 |
| --- | --- | --- |
| 私信 Chat | 会话背景 #EDEDED，浅色 Header / Composer，白色输入框，白色对方气泡、黑色正文，自身气泡绿色 | `lib/pages/chat/chat_page.dart:609`；`lib/components/chat/shared/chat_ui_library.dart:133`；`lib/components/chat/shared/chat_ui_style_config.dart:202` |
| Buy Gems | 白色 Scaffold / Header，白色商品卡，浅灰任务及说明区域，深色正文；加载、错误、空态也需随页检查 | `lib/pages/gems/gem_wallet_page.dart:182`；`gem_wallet_content.dart`；`gem_wallet_state_panels.dart`；`lib/components/gems/gem_purchase_catalog.dart` |
| Gem Records | 白底 Header / 页面，Tab、记录正文和空态仍为浅色页文字体系 | `lib/pages/gems/gem_records_page.dart:180` |
| Model | 白底页面 / 卡片，浅粉选中卡片、黑色正文、灰色元数据及 Save | `lib/pages/gems/memory_model_page.dart:190`、`:388` |
| 强制升级 | 页面使用 GenesisColors.surface（白色），未包深色主题，正文沿用浅色排版 | `lib/app/version/force_upgrade_gate.dart:159` |
| Page not found | Scaffold 和 Header 未覆盖深色，读取全局白色默认背景 | `lib/pages/common/page_not_found_page.dart:21` |

## Sheet / 弹窗遗漏

| 入口 | 当前实现 | 代码位置 |
| --- | --- | --- |
| Gems 不足 → 充值 Sheet | 无显式深色主题包装，底板受调用处主题影响；内部商品卡固定白色、说明卡 #F7F7F7、浅色边框与深色文字。即使从深色页面打开，也存在白卡片 | `lib/components/gems/gem_balance_prompt.dart:41`；`lib/components/gems/gem_purchase_bottom_sheet.dart:50`、`:299`、`:366`；`lib/components/gems/gem_purchase_catalog.dart:196` |
| World 等待首个 Tick 弹窗 | 实际存在自动入口；使用原生 AlertDialog，未覆盖深色背景/正文或复用 GenesisActionBox，读取全局浅色主题 | `lib/pages/world/world_page_detail_sync.dart:345`；`lib/components/world_tick1_wait_dialog.dart:129` |

## 已处理的分支遗漏（2026-09-10）

1. **Worldo 首次加载失败：已修复。** 错误页显式使用 `GenesisColors.darkBackground`，错误文字使用 `darkTextSecondary`，保留 Retry 行为。
2. **Worldo Detail → Launch Preview：已按要求删除。** 移除入口、组件、专用预览数据处理和样式，不影响 Opening 预览或 World Events。

3. **Setup Your Role：已适配。** Sheet 使用 raised 背景；Preset / Custom 使用深色样式，Playing Tab 及专用状态、加载器、Enter 分支已删除；Launch 为纯文字按钮。

## 全局默认与转场风险

- 根 App 仍为 `GenesisTheme.light()`：`lib/app/genesis_app.dart:31`。全局 ColorScheme 是 Brightness.light，Scaffold 默认 GenesisColors.surface（白色）：`lib/ui/theme/genesis_theme.dart:34`、`:50`。
- 当前深色主要依赖局部 GenesisDarkTheme、DiscussDarkTheme 或组件显式颜色；公共 Sheet、Header、CreateFormTheme 等仍保留浅色默认/分支。不能据正常页面深色就认定所有默认组件已经深色。
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

1. Buy Gems / Gem Records / 充值 Sheet / Model 作为一组处理。
2. 私信页面及 Composer / 气泡。
4. 首 Tick 等待弹窗、强制升级及未知页面。
5. 最后统一全局默认和转场，再逐入口进行真机或模拟器视觉验收；Developer 单独安排。
