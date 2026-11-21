# 中文版回归测试记录（2026-11-19）

本轮按 [中文测试规范](chinese-testing.md) 复用原仓库 24 项门禁，以当前中文程序为主要对象，另增加 `chinese` 结构门禁。英文只用于必要对照及原 RTL 方向性专项。当前仍在执行，本文不构成发布验收或“第二阶段全部完成”的证明。

## 环境和证据

- macOS 26.5.2（25F84），Apple Silicon；Xcode 26.6（17F113），未声称使用原文的 Xcode 27。
- 英文行为基线：`b266339003c6897d3c9e5d7d8ca758c6065c5362`。
- 证据目录：`recordings/chinese-acceptance-20261119/`；本次训练/复盘/小游戏最终批次：`provider-final/`；较早基线检查另存 `post-inspector-fix/`、`final-six/`；门禁台账：`zh-ledger.json`。
- 中文交互实例必须有本次运行、本门禁及对应实例的原始中文菜单证据。未知英文期望拒绝通过；棋谱、棋格和用户数据保持原文。
- GUI 自动化使用独立程序标识、临时数据及显式静默替身，不发真实模型请求、不录音、不播放声音。另有两个明确启用的真实 DeepSeek 探针（见下），同样不录音或播放。历史用户对中文语音的确认单独保留，未冒记本轮重新听审。

## 已发现并处理的问题

| 类别 | 原因和处理 | 结果边界 |
| --- | --- | --- |
| 实际界面性能缺陷 | 中文组合译文在每个列表行反复扫描全部长短语，导致主线程高 CPU 和界面无响应。增加有界缓存及规范化字节预筛选，保留精确翻译、替换顺序和原替换操作 | 针对性 22 项测试通过；2050 次行文本转换约 0.023 秒；完整课程门禁通过。完整单元回归仍单独记录 |
| 实际图表拖动缺陷 | 详情区的图表拖动触发窗口背景拖动，窗口横移 155 点，旧绝对坐标下的第 30 步终点因此落在第 11 步。仅详情区使用不允许窗口背景拖动的 hosting view，保留标题栏拖窗 | 中文、同项目英文及旧提供方诊断均复现旧问题；修复后默认 DeepSeek 短探针两次拖到第 30 步，窗口和图表位置均不变。完整本机门禁正按新公共源码重跑 |
| 实际训练难度漏译 | `TrainingOpponentLevel.title` 直接返回英文，导致中文菜单仍显示 Gentle / Steady / Strong | 改用已有中文目录；难度原始值、棋力和搜索配置不变。训练完整界面回归已在最终源码通过 |
| 活动标题适配 | “课程名 · Play on · Your turn” 的阶段被错误切入课程名。按首个分隔符划分课程名与完整阶段说明 | 适配器 13 项检查及中文课程实操通过 |
| 棋盘定位适配 | 中文棋盘与“棋盘”课程同名；测试辅助工具仍按英文找棋盘 | 使用实际语言标签及 AXGrid 角色；无点击重启用稳定棋格 ID；原始棋格标签精确比较，中文选中状态另验 |
| 焦点辅助窗口 | 本机空白区不足；独立审阅又发现内容矩形没有覆盖标题栏 | 保留 120 点内容区、真实外窗点击和原焦点断言；候选及显示后均检查完整窗框不遮挡目标且在可用区域 |
| 移动安装路径 | `/var` 与 `/private/var` 指向同一位置，原脚本只规范化了一侧 | 两侧均解析实际路径，并补查移动后的中文课程、教学译文及编译后的设置菜单译文；待重跑 |
| 删除的开发占位文字 | 严格适配器拒绝未收录的旧英文占位期望 | 保留该原始文字不得出现的检查，显式标为原始占位文字；待重跑 |

评估图证据在 `graph-probe-{deepseek,legacy,geometry,window,inspector-fix}/`。同项目英文界面对照不等同于独立构建的原英文基线；图表与选择逻辑的源码对照和实际窗口几何记录共同用于定位，未据此推断原版已通过或原版必然失败。

启动性能原测为 2.06 / 2.04 秒，包含新增测试适配开销。移出适配准备及证据写盘后，实际 AX 就绪观测为 2.002786875 秒（约 2.003）；原严格 `<2` 判定保留为失败，用户随后明确接受该 2.003 秒样本。后续样本包括 2.196、1.995、1.979 秒，分别留档；不把更慢的新样本自动扩展为人工通过。生命周期先执行功能断言，再报告新样本的原始自动耗时判断。人工验收记录绑定产品源码指纹，与本次功能结果和新样本耗时分开呈现。

## 训练、复盘、小游戏专项：已完成

最终证据目录为 `recordings/chinese-acceptance-20261119/provider-final/`。三个门禁均通过，结束后按当前源码重新查询台账，均为 `current`；未生成整套发布验收文件。

| 门禁 | 原业务与中文 DeepSeek 验证 | 证据 |
| --- | --- | --- |
| training-b-pointer | 保留升变、电脑回复、悔棋、难度、结果、复盘入口、课程书签；中文卡片打开不记帮助，明确授权提问后使用训练 FEN、记录帮助且不走棋，文字提问零录音，可停止朗读 | training-b-pointer-results.json；training-deepseek-receipt.json；本次中文菜单 AX 证据 |
| pawn-duel | 8 种小游戏的实际操作与回复、已证明事实保留；按稳定标识实际点击朗读/停止，精确文本、再次朗读、关闭/重启均验证，模型请求和麦克风启动均为零 | pawn-duel-results.json；mini-review-speech-receipt.json；mini-review-reading.png |
| review-ui | 保留中文导入、错误提示、64 格无障碍、导航/输入焦点、假设分支、保存恢复/退出持久化及原性能断言；默认教练使用当前复盘，中文回答最新优先，失败/重试/停止、在途切节点取消均通过，练习棋盘未被修改 | review-ui-results.json；review-deepseek-receipt.json；shutdown-persistence-result.json；AX 请求/结果 |

三项主流程均使用中文。原单元及规则断言按原入口语言原样复用，未用英文界面通过替代中文版验收。五组直接相关 XCTest 共 54 项、0 失败（DeepSeek 18、训练规则 12、授权 4、控制栏 19、小游戏复盘 1）；其中包含工具续接、披露前记录帮助、在途更换训练尝试/复盘节点取消，以及旧朗读隔离。另有 13 项语言适配器自测通过。没有把这些专项测试冒记为完整 unit 或所有 25 项门禁重跑。

五组最终 XCTest 日志（合计 54 项，均 0 失败）：

| 组别 | 项数 | 本轮日志 |
| --- | --- | --- |
| DeepSeek 教练 | 18 | [CheckmateCoreTests.DeepSeekCoachTests.log](../recordings/chinese-acceptance-20261119/provider-final/CheckmateCoreTests.DeepSeekCoachTests.log) |
| 训练规则 | 12 | [CheckmateDomainTests.PositionGameRulesTests.log](../recordings/chinese-acceptance-20261119/provider-final/CheckmateDomainTests.PositionGameRulesTests.log) |
| DeepSeek 授权 | 4 | [CheckmateNativeTests.DeepSeekConsentTests.log](../recordings/chinese-acceptance-20261119/provider-final/CheckmateNativeTests.DeepSeekConsentTests.log) |
| 控制栏 | 19 | [CheckmateNativeTests.ControlBarModelTests.log](../recordings/chinese-acceptance-20261119/provider-final/CheckmateNativeTests.ControlBarModelTests.log) |
| 小游戏复盘窗口 | 1 | [CheckmateNativeTests.MiniGameReviewSheetTests.log](../recordings/chinese-acceptance-20261119/provider-final/CheckmateNativeTests.MiniGameReviewSheetTests.log) |

真实 DeepSeek 小样也已分别通过，未自动重试：

| 小样 | 实际模型与已验证合同 | 实际 token 用量 | 证据 |
| --- | --- | --- | --- |
| review | deepseek-flash；作用域 read-only-review、当前节点 1 与 FEN 一致；inspect_piece(d4) 的实际成功结果与本地检查逐字段一致；中文回答且棋盘不变 | 2,844 | live/review/result.json |
| training | deepseek-flash；作用域 training、训练 FEN 一致；指定棋格的 inspect_piece 实际成功，帮助已记录，中文回答且训练动作/练习棋盘不变 | 3,817 | live/training/result.json |

真实小样合计 6,661 tokens，不代表逐句棋理正确或所有边界情况已经验证。静默朗读检查证明传入驱动的文字和状态合同；麦克风及扬声器效果仍引用此前独立联调和用户确认，没有冒记为本轮再次实测。

中途失败记录保留：难度菜单漏译为产品问题；嵌套 JSON 的字符串比较、格式模板查询、SwiftUI 按钮定位和英文 Chessboard 期望为测试适配问题。没有放宽棋局、帮助记录、事实或性能断言以取得通过。最终源码清单为 `provider-final/source-hashes.json`，SHA-256：`86df88494de1cc7ff316898c247fd09bd9f406a1b24d59c5a7342d9d2383936b`。

## 尚不能认定通过的范围

- 当前 DeepSeek 教练不支持网络对局作用域，属于功能待适配；不能宣称已复制原版的全部网络教练能力。
- Bonjour 需要测试签名信任及环境准备记录；未擅自修改证书信任。
- 双机局域网测试等待第二台 Mac；Intel 实际运行缺 Rosetta 条件，交叉编译不算实测通过。
- 门禁的源码和校验定义必须仍新鲜；运行中改动导致的失效记录不得算通过。完整发布仍需原全套入口成功及原聚合验收文件。

本轮修复仍在工作区和测试产物中，尚未替换用户已安装的预览程序或发布新版本。

独立 agent 的计划及定向实现复核见 [审计记录](chinese-testing-audit.md)。审计通过不等于程序或全部门禁通过。
