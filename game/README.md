# Rummi Lite — 轻量版拉密 (Godot 4.3)

基于 Rummikub 调研报告设计的移动竖屏单人分数挑战(Balatro式),保留"桌面自由重组"核心机制。

## 运行

用 Godot 4.3+ 打开 `game/` 目录(导入 `project.godot`),F5 运行。竖屏 720x1280,鼠标/触摸拖拽。

## Web 版导出(手机实机测试)

1. 首次: Godot 编辑器 → 编辑器 → 管理导出模板 → 下载并安装(对应当前版本)
2. 项目 → 导出 → 选择已配好的 "Web" 预设 → 导出项目,路径保持默认(`../build/web/index.html`, **入口必须叫 index.html**, itch.io/GitHub Pages 都要求)
3. 本地调试: 项目根目录 `python3 serve_web.py`(自签HTTPS), 手机同WiFi访问
4. 长期测试入口(推荐): `python3 package_web.py` 打包 zip → 上传 itch.io(HTML项目, 可设私密) → 手机开页面 → 已启用PWA: 首次加载后可离线玩, "添加到主屏幕"即全屏App体验

预设已关闭线程支持(`thread_support=false`)。手机经局域网 IP 访问必须 HTTPS(安全上下文),`serve_web.py` 已内置自签证书。命令行导出: `godot --headless --path game --export-release "Web"`。

**中文字体注意**: Web 端没有系统字体,中文靠 `assets/fonts/cjk_subset.ttf`(子集化,~70KB)。若新增 UI 文案中出现子集外的汉字,会显示为方块——需要重新子集化:把新字加入后用 `pyftsubset DroidSansFallbackFull.ttf --text-file=chars.txt --output-file=assets/fonts/cjk_subset.ttf` 重新生成。

## 牌池与规则(轻量版)

- 43张牌: 1-7 × 3色(红/蓝/橙) × 2份 + 1张Joker(★)
- 顺子: 同色连续数字 ≥3张(最长7),按摆放顺序升序或降序
- 刻子: 同数字不同颜色,3色下恰好3张
- Joker 按所在位置取隐含值,推算超出1-7范围则非法
- 无首次下牌30分门槛(分数挑战模式下不需要)

## 对局流程(爬塔分数挑战, 详见 ../玩法设计.md)

1. 每层5回合,目标分递增(40/60/85/125/180/260/380/550, 共8层),过层后牌库重置重发
2. 每回合自由地: 从牌架拖牌上桌 + **任意重组桌面已有牌**;「出牌」结算,全桌合法才生效
3. **计分 = chips × 倍率**: chips=新出牌面值之和; 倍率=1+0.5×被实质重组的旧牌数(原组被拆/牌被挪才算, 仅接龙扩充不算)
4. 「换牌」(每层2次): 选任意手牌洗回牌库换抽等量
5. 结算后摸1张;手牌打空+20并补5张
6. 「整理」排序;「提示」(每层3次)高亮可组手牌;「撤回」回到回合开始

## 代码结构

| 文件 | 职责 |
|---|---|
| `scripts/rules.gd` | 纯规则: 牌池、牌组校验(含Joker)、计分、提示搜索。无UI依赖,可headless测试 |
| `scripts/tile_node.gd` | 单张牌视觉(奶油底/彩色数字/金边新牌高亮)+拖拽 |
| `scripts/main.gd` | 布局、桌面/牌架网格、回合流程、结算、胜负 |
| `scripts/relics.gd` | 肉鸽成长接口(遗物hook: 改分/改抽牌数 + 示例遗物),为爬塔循环预留 |

## 后续爬塔方向(已预留接口)

- 层数递增目标分/递减回合数,Boss层特殊规则
- 过关奖励遗物(`RelicManager.sample_relics` 已有示例: 顺子x1.5、多抽1张)
- 消耗品: 重抽/指定抽/临时Joker
- 牌库改造: 加牌/删牌/牌加属性
