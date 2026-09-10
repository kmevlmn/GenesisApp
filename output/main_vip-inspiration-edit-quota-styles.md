# main_vip：Inspiration / Edit 次数提示样式（Token 对照版）

更新日期：2026-09-10  
原实现基线：`main_vip`（`fe2aa072`）  
规范依据：当前 `main_ui_black` 工作区的 `genesis_app/AGENTS.md` 与 `lib/ui/tokens/` 定义。  
适用位置：Location Chat 中的 Inspiration 与 Edit 次数提示。

本文是更新后的样式约定与实现映射，不表示 main_vip 代码已完成迁移。两处提示继续复用 `LocationChatSubscriptionPrompt`。

## 共用样式与 Token

| 样式项 | 应引用的 Token / 样式 | 当前值或目标效果 |
| --- | --- | --- |
| 字体基础 | `GenesisTypography.resolve(context, style.bubbleTextStyle)` | 继承主题字体及聊天正文样式 |
| 字号 | 局部 `copyWith(fontSize: 13)` | 13px；现有排版 token 没有匹配的 13px 档位，保留局部覆盖 |
| 字重 | `style.bubbleTextStyle.fontWeight` | w400 |
| 行高 | `style.bubbleTextStyle.height` | 1.4，约 18.2px |
| 普通文字颜色 | `style.bubbleTextStyle.color`，默认来自 `kChatScenePlateBubbleTextStyle` | `#F4F3F6`；保留聊天专用字色 |
| 次数及双引号颜色 | **`GenesisColors.redSecondary`** | **`#FF8A9A`**；替换旧 `GenesisColors.brand` / `#FF2442` |
| `Get more >` 颜色 | **`GenesisColors.redSecondary`** | **`#FF8A9A`**；替换旧 `GenesisColors.brand` / `#FF2442` |
| 底色 RGB | `GenesisColors.darkBackground` | `#151517` |
| 底色不透明度 | 继续使用 `style.selfBubbleColor.a` | 默认 60%，透明度为 40%；默认结果等价于 ARGB `#99151517` |
| 背景模糊 | `GenesisBlur.strong`，经 `kChatScenePlateBubbleBlurSigma` / `style.bubbleBackdropBlurSigma` 传递 | sigmaX / sigmaY = 14 |
| 圆角 | 默认值对应 `GenesisRadii.panel`（`GenesisRadii.xl`）；组件继续读取 `style.bubbleBorderRadius` | 四角均为 14px |
| 内边距 | `kChatScenePlateBubblePadding`，经 `style.bubblePadding` 传递 | 左右 13px，上下 11px |
| Inspiration 提示上间距 | `GenesisSpacing.lg` | 距推荐卡片 10px |
| Edit 提示上间距 | `GenesisSpacing.xl` | 距操作按钮行 12px |

表中的数值用于核对效果；存在对应 token 时，实现应引用 token，不重复硬编码。

## 排版与交互

| 项目 | 约定 |
| --- | --- |
| 排版 | 两行，`Get more >` 单独一行；可用宽度不足时允许自动换行 |
| 对齐 | 提示框和文字均居中 |
| 宽度 | 随内容自适应，受父容器可用宽度限制 |
| 点击范围 | 整个提示框 |
| 点击行为 | 打开 Subscription 购买 Sheet |

尺寸中的 px 对应 Flutter 逻辑像素。系统文字缩放可能影响实际文字尺寸及换行。

## 文案与位置

| 提示 | 第一行文案 | 第二行文案 | 上间距 Token |
| --- | --- | --- | --- |
| Inspiration | `Free inspiration uses left: "3"` | `Get more >` | `GenesisSpacing.lg`（10px） |
| Edit | `Free Edition uses left: "3"` | `Get more >` | `GenesisSpacing.xl`（12px） |

两处第一行中的数字及双引号、第二行的完整 `Get more >` 均使用 `GenesisColors.redSecondary`。

### Inspiration

```text
Free inspiration uses left: "3"
Get more >
```

提示位于推荐卡片轮播下方，整体在对话区域居中；父容器宽度使用推荐卡片宽度，提示底框仍随文字内容自适应。

### Edit

```text
Free Edition uses left: "3"
Get more >
```

提示位于操作按钮行下方，整体在对话区域居中。`Edition` 保留原实现用词。

## 迁移边界

- 本次明确的视觉变更：两个提示中的次数及双引号、`Get more >`，由品牌红改为 `redSecondary`。
- 普通文字 `#F4F3F6` 是独立的聊天字色，与 `darkTextPrimary`（95% 白）并不相同。按现行规范保留，不因为颜色接近而替换；若后续要统一为一级白字，应作为单独的视觉调整。
- 底色继续使用聊天提示的 60% 不透明度，RGB 从 `darkBackground` 派生。不要改成 `darkOverlayBackground`：后者是公共操作弹窗与生成等待浮层使用的 40% 抬升背景，语义和视觉都不同。
- 默认背景可表示为 `GenesisColors.darkBackground.withValues(alpha: style.selfBubbleColor.a)`。通用组件仍需保留当前 Narrator 背景选择逻辑，避免覆盖调用方的自定义样式。
- 圆角、内边距及模糊继续通过传入的聊天样式读取；规范 token 应在默认样式或已有语义常量处映射，不应让通用组件失去样式覆盖能力。
- 13px 字号、13px / 11px 聊天气泡内边距没有完全匹配的通用字号 / 间距 token。保留局部字号和已有聊天专用常量，不调整为邻近档位，也不虚构现有 token。

## 原实现状态

- main_vip 基线中的两个次数文案及共用行动文案仍引用 `GenesisColors.brand`；本文将其目标改为 `GenesisColors.redSecondary`。
- 两处 `"3"` 均为写死的演示文案，不代表真实剩余次数。
- 点击 Edit 会展开次数提示，并调用进入编辑页的回调；点击 Inspiration 会收起 Edit 提示并切换推荐区域的展开状态。
- 本次仅修订本文档，未修改页面代码或真实次数逻辑。

## 规范与代码位置

以下路径均相对于 `genesis_app/`：

| 文件 | 用途 |
| --- | --- |
| `AGENTS.md` | 深色颜色、红色层级、透明度变体及 Blur 规范 |
| `lib/ui/tokens/genesis_colors.dart` | `darkBackground`、`redSecondary` 等颜色唯一来源 |
| `lib/ui/tokens/genesis_blur.dart` | `GenesisBlur.strong` |
| `lib/ui/tokens/genesis_radii.dart` | `GenesisRadii.panel` / `xl` |
| `lib/ui/tokens/genesis_spacing.dart` | `GenesisSpacing.lg` / `xl` |
| `lib/ui/tokens/genesis_typography.dart` | 主题字体解析及基础排版 |
| `lib/components/chat/shared/chat_scene_plate_tokens.dart` | 聊天专用内边距、字色、正文样式及模糊映射 |
| `lib/components/chat/shared/chat_ui_library.dart` | Location Chat 默认样式与用户气泡 alpha |
| `lib/components/chat/shared/chat_ui_narrator_message_bubble.dart` | Narrator 背景选择逻辑 |
| `lib/pages/chat/location_chat_reply_actions.dart` | 两处文案、外部间距及共用提示组件 |
