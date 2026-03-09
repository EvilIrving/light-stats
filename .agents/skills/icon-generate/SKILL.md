---
name: icon-generate
description: Generates project SVG logo by reading the project README or code to analyze functionality and theme, then creating an icon per Apple/macOS design guidelines. Use when the user asks for a logo, app icon, or SVG icon for the current project.
---

## 流程

1. **阅读项目**：优先读 `README`、`README.md`、`README.zh.md` 等；必要时浏览项目代码结构或关键文件以理解功能与定位。
2. **分析功能与主题**：归纳应用名称、核心功能（1–3 句）、主题关键词（如：监控、编辑、通讯、开发工具、写作、统计等）。
3. **参照图标体系**：生成前参照下方「图标体系示例」中的视觉语言——大地色底、白/浅色主形与细线、杂志风留白与层级，单枚 logo 应与该体系在风格上一致。
4. **生成 SVG**：在下方模板的安全区容器内绘制背景与图标主体。

### 图标体系示例

以下为一套图标体系，用作造型、配色与版式的参考：

| 示例 | 说明 |
|------|------|
| [logo-example01.jpg](logo-example01.jpg) | 大地色底上的极简图标：白形+细黑线、手与物互动、科技/数据/开发等主题，留白充足。 |
| [logo-example02.jpg](logo-example02.jpg) | 抽象图形体系：几何与有机形、粘土/炭黑/橄榄绿/灰粉等大地色、大留白与清晰层级。 |

## 设计原则

- **圆角**：所有元素均采用圆角设计，iOS Icon 使用连续圆角（squircle）
- **色彩**：粘土、流沙与炭黑的大地色系；温暖、柔和的琥珀色/米色，偏自然与纸质感。
- **版式**：杂志风，大留白，清晰的层级。
- **元素数量**：单枚 logo 应不超过 3 个元素，数量过多会导致辨识困难。

### SVG 结构模板

仅提供画布与安全区容器，不预设颜色或背景；背景与图标内容均在容器内自行定义。

```xml
<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <g transform="translate(512, 512)">
    <!-- 安全区：扣除 15% 边距后的可操作区域，坐标范围 x/y 均为 ±435（870×870）。在此组内定义背景与图标主体 -->
  </g>
</svg>
```

## 更多说明

- 不适用于：照片级图标、复杂插图、动画、品牌 logo 精确复刻
