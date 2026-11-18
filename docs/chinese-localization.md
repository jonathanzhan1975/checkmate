# 简体中文版本使用与维护

## 语言与离线内容

界面跟随 macOS 语言，也可在设置的界面语言选项中选择简体中文或 English，重启生效。新配置在中文界面下默认选择简体中文课程与普通话；已有配置的课程和教练语言保留原值。

设置 → 课程 → 使用简体中文课程，可独立切换课程语言。39 项课程（34 主课、5 项配套练习）的 710 个讲解片段已内置中文文本。实操、82 道习题和训练目录、场景的补充文本通过 `content.zh-Hans.json` 在显示层映射，原始选项值、答案、棋盘与教学规则不变。

有中文文本但没有完整录音时，可静音阅读、暂停和逐步学习，不会替中文文本播放英文录音。完整录音包就绪后，课程按实际录音时长安排棋盘动作。用户缓存损坏时保留有效内置文本；源数据不匹配的补充译文不加载。

## DeepSeek 备用文字翻译

默认使用 Codex 登录账户的翻译服务。设置 → 课程中可显式选择“使用 DeepSeek 备用文字翻译”。切换本身不发起翻译请求，也不会自动从 Codex 切换到付费 API。翻译会复用已有文本；录音仍通过原语音服务生成。

本机密钥仅从 `DEEPSEEK_API_KEY`（兼容 `Deep_Seek_API_Key`）环境变量读取，不写入课程、日志或导出的语言包。终端中可隐藏输入：

```zsh
read -rs 'DEEPSEEK_API_KEY?请输入密钥：'
echo
export DEEPSEEK_API_KEY
launchctl setenv DEEPSEEK_API_KEY "$DEEPSEEK_API_KEY"
```

重新启动应用以继承环境。`launchctl setenv` 不保证重启电脑后保留，需要时重新配置。不要把密钥写进仓库。

文字翻译默认请求 `deepseek-flash`。只对明确的限流或临时服务拒绝进行最多两次重试；认证、余额、译文校验错误停止，网络超时不自动重复计费。响应必须通过课程 ID、片段顺序、结构和棋谱记号校验才保存。用量记录保留实际提供商、模型和返回 token 用量。

## 普通话录音与可恢复生成

当前采用已验证的 Codex 登录 / OpenAI Realtime、Cedar 音色、24 kHz 单声道 16 位 PCM/WAV，复用原有 `PCM.isPlausible` 和 `saidMatches` 校验。没有关闭或降低朗读校验。中文朗读稿中的英文数字词已改为中文数字，原始坐标与 SAN/UCI 记号保持不变。

在已标记的构建/测试机上运行：

```sh
python3 scripts/test_host.py narration
python3 scripts/fresh-sources.py .build -- swift run CheckmateChineseNarration --generate --output recordings/chinese --all
python3 scripts/fresh-sources.py .build -- swift run CheckmateChineseNarration --verify --output recordings/chinese
```

生成最多同时处理 3 个片段，跳过脚本与音频哈希均有效的已完成录音。失败即停止并保留已完成结果；拒绝的音频仅保存到 `recordings/chinese/rejected` 用于排查，不进入可用录音包。修正后显式重跑命令继续。朗读稿发生变化时只使受影响的录音失效，不重复生成未变化的录音。

完整验证通过后，生成离线包或安装到本机开发版的数据目录：

```sh
python3 Tools/install-chinese-lessons.py recordings/chinese --archive build/Checkmate-zh-Hans-Lessons.zip
python3 Tools/install-chinese-lessons.py recordings/chinese --install
```

安装器再次核对课程版本和全部文件哈希，原子替换录音文件，保留其他用户数据。被替换的已有语言文件备份到 `recordings/backups`。安装到其他数据目录时使用 `--destination DIRECTORY`。跨机传输离线包时先解压，再将解压后的目录作为 `source` 运行同一安装器。

生成记录、用量与拒绝样本在 `recordings/`，不提交 Git；交付 ZIP 只包含经过完整验证的语言包与验证清单。转录一致性、文件校验与播放测试不能替代人耳对音质、语调和逐句教学同步的评价。

## 验证与范围

```sh
python3 -I scripts/test-chinese-localization.py
bash scripts/acceptance.sh --only unit
CHECKMATE_TEST_LANGUAGE=zh-Hans CHECKMATE_EVIDENCE_DIR=/tmp/checkmate-chinese-ui bash scripts/test-ui.sh
CHECKMATE_TEST_LANGUAGE=zh-Hans CHECKMATE_EVIDENCE_DIR=/tmp/checkmate-chinese-layout bash scripts/test-layout.sh
```

普通测试固定使用 English / en_US，独立中文场景显式选择 zh-Hans。Native SwiftPM 测试先编译字符串目录，确保中文资源与英文复数均参与测试。中文复盘仍使用本地验证事实与局面版本校验，朗读文字不得改写事实；完整实时中文语音教练仍属于第二阶段。
