<div align="center">

<img src="screenshots/logo.svg" width="128" alt="Cadence logo"/>

# Cadence AI 音乐 — iOS

### 随你律动的音乐

[English](README.md) · **简体中文**

[![平台](https://img.shields.io/badge/平台-iOS%2016%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-007AFF?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)

**Cadence** 持续读取你的生理状态，并基于 *同质原理*（iso-principle）实时生成个性化的器乐音乐——先匹配你当前的状态，再逐步将其引导至期望的情绪目标。

本仓库是 [`wtgme/cadence`](https://github.com/wtgme/cadence)（Android）的 iOS 移植版本。目标是与 Android 版本保持功能对等，仅替换平台相关的层（Health Connect → HealthKit，Compose → SwiftUI，ExoPlayer → AVPlayer 等），同时保留完全相同的领域逻辑、提示词和生成流水线。

---

## 科学背景

音乐是日常情绪调节中最有效的策略之一。**同质原理**——先让音乐匹配听者的心理生理状态，再将其引向目标状态——已获得受控实验的支持，相较被动聆听能显著提升积极情绪。从神经生物学的角度看，音乐可调节皮质醇水平、自主神经唤起以及奖赏环路。

这些效应高度依赖音乐属性与听者实时状态之间的 *契合度*。目前没有任何消费级系统能自动实现这一点。Cadence 是一款针对此空白的功能性原型。

---

## 两步式 AI 流水线

```
┌─────────────────────────────────────────────────────────────┐
│                       传感器层                              │
│  心率 · HRV · 血氧 · 睡眠 · 步数 · GPS · 天气               │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              第 1 步 —— 情境翻译                            │
│  LLM —— 任意兼容 OpenAI 的 chat 接口                        │
│  生物特征情境 → 心理状态估计                                │
│  （唤起度 · 效价 · 压力 · 能量 · 专注度）                   │
│  → 歌曲参数（风格标签 · BPM · 情绪 · 强度）                 │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              第 2 步 —— 音乐生成                            │
│  文本到音乐模型（MiniMax、SongGeneration 等）               │
│  歌曲参数 → 器乐 MP3                                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                 预缓冲播放                                  │
│  2 项缓冲 · 无缝切换                                        │
│  情景变化或心率漂移 ±15 bpm 时重新触发                      │
└─────────────────────────────────────────────────────────────┘
```

所有生物特征数据均在 **设备端处理**。仅匿名化的情境摘要会被传输用于音乐生成。

---

## 情景识别

Cadence 通过传感器融合对你的活动情景进行分类，并据此塑造生成结果：

| 情景 | 触发条件 | 音乐意图 |
|---|---|---|
| 跑步 | 速度 > 8 km/h 或心率 > 135 bpm | 高能量、节拍匹配 |
| 步行 | 速度 3–8 km/h | 中等节奏、平稳 |
| 通勤 | 速度 > 25 km/h | 提神、低干扰 |
| 健身 | 手动 | 充满活力、激励性 |
| 专注 | 手动 | 极简、支持专注 |
| 休息 | 低运动量 / 默认 | 缓慢、舒缓、氛围化 |
| 派对 | 手动 | 欢快、社交氛围 |

---

## 研究透明度

应用会实时展示其完整的推理链，让用户理解 *为什么* 生成了这段音乐：

- **生物特征输入** —— 原始传感器读数，附带天气和位置情境
- **心理状态估计** —— 量化维度：唤起度、效价、压力、能量、专注度、情绪
- **音乐推荐** —— 所选风格、流派标签与歌词框架
- **覆盖与反馈** —— 用户可调整任意参数或评价曲目；口味档案会随时间适配

这种设计支持知情同意与用户自主权——这是健康场景下负责任 AI 部署的核心原则。

---

## 系统要求

- iOS 16.0 或更高
- 支持 **HealthKit** 的 iPhone（iPhone 8 / SE 2 或更新机型）
- Apple 开发者账号（免费账号可个人侧载；App Store / TestFlight 需付费账号）
- 用于实时生物特征采集的可穿戴设备：Apple Watch，或任何向 iOS 健康 app 写入数据的设备（Whoop、Oura、Garmin Connect 等）

---

## 配置

Cadence 的两个流水线阶段各自调用一个 HTTP 接口，两者都可在应用内通过 **API 设置**（齿轮图标 → API SETTINGS）进行配置。你可以自由搭配：

- **第 1 步 —— LLM**（生物特征 → 歌曲风格）：任意兼容 OpenAI 的 chat 接口——[OpenRouter](https://openrouter.ai/)、本地 Ollama / vLLM 服务，或随附的 `cadence-api` LLM 接口。
- **第 2 步 —— 音乐生成**：文本到音乐接口，例如 [MiniMax Music](https://www.minimax.io/)、自托管的 [SongGeneration](https://github.com/tencent-ailab/SongGeneration) 服务，或随附的 `cadence-api` 音乐接口。

### 自托管参考服务器（可选）

[**wtgme/cadence-api**](https://github.com/wtgme/cadence-api) 将两个流水线阶段打包为单个 FastAPI 服务：一个由你选择的模型支持的 OpenAI 兼容 chat 接口，加上一个 SongGeneration 封装。若你想要完全的本地控制或私有 GPU 部署会很有用。**它并非必需**——任何兼容的第三方 API 都可使用。

### 编译期默认值

默认值位于 [`Cadence/BuildConfig.swift`](Cadence/BuildConfig.swift)，与 Android 的 `local.properties` 一一对应：

```swift
static let signal2StyleBaseUrl: String = "https://chat.cadencemusics.uk/v1"
static let signal2StyleApiKey: String  = "dummy"
static let signal2StyleModel: String   = "google/gemma-4-E4B-it"

static let songGenBaseUrl: String = "https://api.cadencemusics.uk/v1/music_generation"
static let songGenApiKey: String  = "dummy"
static let songGenModel: String   = "SongGeneration-v2-large"
```

用户在 **API 设置** 界面填入的值会被持久化到 `UserDefaults`，每次启动时都会覆盖 BuildConfig 中的默认值。

### 构建

使用 Xcode 15+ 打开 `Cadence.xcodeproj`，并选择运行目标：

```bash
# Debug 构建（模拟器）
xcodebuild -scheme Cadence -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator build

# 单元测试
xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:CadenceTests test
```

### 必需的 Capability（Xcode → Signing & Capabilities）

- **HealthKit** —— 读取心率、HRV、睡眠、血氧、步数、卡路里、距离、血压、体温、爬楼层数、锻炼时长等数据。免费 Apple ID 即可。
- **Background Modes** —— Audio（息屏时继续播放）与 Location updates（场景识别持续运行）。已通过 `project.pbxproj` 中的 `INFOPLIST_KEY_UIBackgroundModes` 预先配置。

---

## 架构

Clean Architecture · MVVM · 轻量级内置依赖注入 · Swift Concurrency + Combine · SwiftUI · AVPlayer

```
Cadence/Cadence/
├── Models/           Scene · SensorState · GeneratedSong · SongParams · MentalState …
├── Domain/           SceneDetector · SceneStateMachine · PromptBuilder · ReadinessCalculator · LLMParamsBuilder
├── Data/
│   ├── Api/          GenerationRepository · MusicRepository · SongGenerationBackend · StreamingResult
│   ├── Sensor/       HealthDataManager · HealthExtrasRepository · SleepRepository · LocationRepository · WeatherRepository · SensorStateCollector
│   ├── Settings/     ApiSettings · ApiSettingsRepository
│   ├── Adjustment/   UserAdjustmentRepository
│   ├── Taste/        TasteMemoryRepository(Impl)
│   ├── Session/      LastSessionParamsRepository
│   └── Onboarding/   OnboardingRepository
├── Audio/            MusicOrchestrator · AudioBufferManager · MusicPlayer · GenerationSemaphore
├── DI/               DIContainer（内置 Factory 风格容器）
└── UI/
    ├── Theme/        CadenceColor · CadenceFont
    ├── Components/   PrimaryCadenceButton · StepDots · KeyboardObserver
    ├── Onboarding/   Welcome · Permissions · ApiSetup · Ready · OnboardingFlowView
    ├── Player/       PlayerScreen · PlayerSheetContent · AdjustmentPanel · AIReasoningPanel · WaveformVisualizer · ActivityPickerMenu
    ├── Settings/     SettingsScreen · ApiSettingsForm · SettingsViewModel
    └── Debug/        DebugScreen
```

---

<div align="center">

*行为与 Android 版本保持一致。Android 源码见 [`wtgme/cadence`](https://github.com/wtgme/cadence)。*

</div>
