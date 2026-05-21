import Foundation

/// Lightweight in-tree DI container. Single-source-of-truth for shared instances,
/// mirroring the Hilt SingletonComponent on Android. Resolution is by typed property,
/// not by string lookup — refactor-safe and compile-time-checked.
///
/// Bootstrapping happens once at app launch via `bootstrap()`. After that, screens
/// pull dependencies via `DIContainer.shared.<property>`.
final class DIContainer {
    static let shared = DIContainer()

    // ── Singletons (created on first access via the bootstrap-or-lazy pattern) ──
    private(set) var readinessCalculator: ReadinessCalculator!
    private(set) var sceneDetector: SceneDetector!
    private(set) var promptBuilder: PromptBuilder!
    private(set) var sceneStateMachine: SceneStateMachine!

    private(set) var apiSettingsRepository: ApiSettingsRepository!
    private(set) var userAdjustmentRepository: UserAdjustmentRepository!
    private(set) var onboardingRepository: OnboardingRepository!
    private(set) var tasteMemoryRepository: TasteMemoryRepository!
    private(set) var lastSessionParamsStore: LastSessionParamsStore!

    private(set) var locationRepository: LocationRepository!
    private(set) var healthDataManager: HealthDataManager!
    private(set) var sleepRepository: SleepRepository!
    private(set) var healthExtrasRepository: HealthExtrasRepository!
    private(set) var weatherRepository: WeatherRepository!
    private(set) var motionActivityRepository: MotionActivityRepository!
    private(set) var workoutSessionRepository: WorkoutSessionRepository!
    private(set) var sensorStateCollector: SensorStateCollector!

    private(set) var generationBackend: GenerationBackend!
    private(set) var generationRepository: GenerationRepository!
    private(set) var paramsBuilder: ParamsBuilder!
    private(set) var audioBufferManager: AudioBufferManager!
    private(set) var musicOrchestrator: MusicOrchestrator!

    private init() {}

    func bootstrap() {
        // Domain
        readinessCalculator = ReadinessCalculator()
        sceneDetector = SceneDetector()
        promptBuilder = PromptBuilder()
        sceneStateMachine = SceneStateMachine(detector: sceneDetector)

        // Data / persistence
        apiSettingsRepository = ApiSettingsRepository()
        userAdjustmentRepository = UserAdjustmentRepository()
        onboardingRepository = OnboardingRepository()
        let tasteImpl = TasteMemoryRepositoryImpl()
        tasteMemoryRepository = tasteImpl
        lastSessionParamsStore = LastSessionParamsRepository()

        // Sensors
        locationRepository = LocationRepository()
        healthDataManager = HealthDataManager()
        sleepRepository = SleepRepository()
        healthExtrasRepository = HealthExtrasRepository()
        weatherRepository = WeatherRepository()
        motionActivityRepository = MotionActivityRepository()
        workoutSessionRepository = WorkoutSessionRepository()
        sensorStateCollector = SensorStateCollector(
            locationRepository: locationRepository,
            healthDataManager: healthDataManager,
            sleepRepository: sleepRepository,
            healthExtrasRepository: healthExtrasRepository,
            weatherRepository: weatherRepository,
            motionActivityRepository: motionActivityRepository,
            workoutSessionRepository: workoutSessionRepository,
            readinessCalculator: readinessCalculator,
        )

        // Network
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        generationBackend = SongGenerationBackend(cacheDir: cacheDir, apiSettings: apiSettingsRepository)
        generationRepository = MusicRepository(
            backend: generationBackend,
            tasteMemory: tasteMemoryRepository,
            userAdjustmentRepository: userAdjustmentRepository,
            apiSettings: apiSettingsRepository,
        )
        paramsBuilder = LLMParamsBuilder(musicRepository: generationRepository, promptBuilder: promptBuilder)

        // Audio
        audioBufferManager = AudioBufferManager(
            musicRepository: generationRepository,
            paramsBuilder: paramsBuilder,
            promptBuilder: promptBuilder,
            userAdjustmentRepository: userAdjustmentRepository,
            lastSessionParams: lastSessionParamsStore,
            audioCacheDir: cacheDir,
        )
        musicOrchestrator = MusicOrchestrator(
            sensorStateCollector: sensorStateCollector,
            sceneDetector: sceneDetector,
            sceneStateMachine: sceneStateMachine,
            bufferManager: audioBufferManager,
            tasteMemoryRepository: tasteMemoryRepository,
            userAdjustmentRepository: userAdjustmentRepository,
        )
    }
}
