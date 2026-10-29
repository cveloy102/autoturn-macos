import AppKit
import UserNotifications

final class SetupAssistantState {
    static func shouldOffer(_ state:SetupReadiness,newBuild:Bool,loadingKeychain:Bool,serviceChecked:Bool,keychainPromptNeeded:Bool = false) -> Bool {
        if loadingKeychain && !keychainPromptNeeded { return false }
        if state.stage == .location && !state.locationChecked { return false }
        if state.stage == .service && !serviceChecked { return false }
        if state.stage == .notifications && state.notifications == .unknown { return false }
        return state.stage != .ready
    }
    var window: NSWindow?
    var reviewing = false
    var loadingKeychain = true
    var keychainPromptNeeded = false
    var keychainError: String?
    var needsSettingsSave = false
    var serviceChecked = false
    var installingService = false
    var serviceMessage = ""
    var notifications = NotificationAccess.unknown
    var notificationReadInFlight = false
    var automation = SetupAutomation()
    var lastRead = Date.distantPast
    var lastPresented = "", rendered = ""
    var accessReadInFlight = false
}

enum SetupAction { case keychain, profile, location, service, notifications, notificationSettings, skipNotifications, refresh, finish, later }

enum SetupAssistantView {
    static func make(_ state: SetupReadiness, loading: Bool, version: String, action: @escaping (SetupAction) -> Void, files: @escaping ([URL]) -> Bool = { _ in false }) -> NSView {
        let root = ProfileDropView(frame:NSRect(x:0,y:0,width:580,height:620)); root.autoresizingMask = [.width,.height]
        root.widthAnchor.constraint(equalToConstant:580).isActive = true
        root.dropped = files; fill(root)
        let content = stack(spacing:16); pin(content,inside:root,inset:28)
        content.addArrangedSubview(label("AUTOTURN / \(version)",size:12,color:Palette.red))
        let title: String, detail: String
        switch state.stage {
        case .keychain:
            title = "1 / Доступ к профилям"
            detail = "Профили хранятся в Связке ключей macOS. Если появится системный запрос AutoTurn, выбери «Разрешить» или «Разрешать всегда». Пароль вводится только в системном окне macOS.\n\nЕсли Связка ключей заблокирована — разблокируй её и повтори проверку."
        case .profile:
            title = "2 / Профиль VPN"
            detail = "Добавь файл .conf от своего VPN-сервера. В разделе «Профили» можно отметить основной: новое подключение всегда начинается с него, остальные используются как резервные."
        case .location:
            title = "3 / Определение домашнего Wi-Fi"
            detail = "Для режима «Авто» macOS требует доступ к геолокации, чтобы сообщить имя Wi-Fi. В системном запросе выбери «Разрешить».\n\nЕсли доступ уже отклонён: «Конфиденциальность и безопасность → Службы геолокации» — включи службы геолокации и AutoTurn. Затем вернись сюда. Координаты не сохраняются и не отправляются."
        case .service:
            title = "4 / VPN-служба"
            detail = "Проверяем службу автоматически. Если её нет или требуется обновление, появится системный запрос macOS — подтверди его и введи пароль администратора. Дождись ответа службы: мастер продолжится сам. Если выбран «Выкл», он сохранится: VPN не включится."

        case .notifications:
            title = "5 / Уведомления об обновлениях"
            detail = "Разреши уведомления, чтобы узнавать о новой версии AutoTurn. Это необязательно для VPN.\n\nЕсли доступ отклонён: «Системные настройки → Уведомления → AutoTurn» — включи «Допуск уведомлений». Можно продолжить без них."
        case .ready:
            title = "Все необходимые разрешения есть"
            detail = "✓ Доступ к сохранённым профилям\n✓ Профиль VPN\n✓ Геолокация для «Авто» проверена\n✓ VPN-служба доступна\n\nAutoTurn продолжит проверять необходимые разрешения. Если доступ отозван, появятся инструкции по восстановлению. Домашние сети можно задать на вкладке «Дом»."
        }
        content.addArrangedSubview(label(title,size:22))
        content.addArrangedSubview(label(detail,size:13,color:Palette.dim))
        if state.pendingImports > 0 { content.addArrangedSubview(label("Файлы приняты: \(state.pendingImports). Импорт начнётся после текущей операции и проверки доступа.",size:11,color:Palette.green)) }
        if state.stage == .profile { content.addArrangedSubview(profileDropZone(files)) }
        content.addArrangedSubview(line())
        func button(_ title:String,_ value:SetupAction,_ primary:Bool = false) {
            let button = ActionButton(title,primary:primary) { action(value) }
            content.addArrangedSubview(button)
        }
        switch state.stage {
        case .keychain:
            if loading { content.addArrangedSubview(label("Проверяем доступ к Связке ключей…",size:12)) }
            else { button("Повторить запрос доступа",.keychain,true) }
        case .profile: button("Добавить профиль .conf…",.profile,true)
        case .location:
            if !state.locationChecked { content.addArrangedSubview(label("Проверяем разрешение геолокации…",size:12)) }
            else { button("Разрешить определение Wi-Fi…",.location,true); button("Я разрешил — проверить",.refresh) }
        case .service:
            if state.serviceInstalling || !state.serviceChecked {
                content.addArrangedSubview(label(state.serviceMessage.isEmpty ? "Проверяем существующую VPN-службу…" : state.serviceMessage,size:12))
            } else {
                if !state.serviceMessage.isEmpty { content.addArrangedSubview(label(state.serviceMessage,size:11,color:Palette.dim)) }
                button("Установить или обновить VPN-службу…",.service,true); button("Проверить службу",.refresh)
            }
        case .notifications:
            if state.notifications == .denied { button("Открыть настройки уведомлений…",.notificationSettings,true) }
            else { button("Разрешить уведомления",.notifications,true) }
            button("Продолжить без уведомлений",.skipNotifications)
        case .ready: button("Готово",.finish,true)
        }
        if state.stage != .ready { button("Позже",.later) }
        content.addArrangedSubview(NSView())
        for child in content.arrangedSubviews { child.widthAnchor.constraint(equalTo:content.widthAnchor).isActive = true }
        return root
    }
}

extension Controller {
    var setupBuild: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "dev" }
    var setupReadiness: SetupReadiness {
        if preview, let state = setupTestReadiness { return state }
        var state = SetupReadiness()
        state.keychainReady = !setup.loadingKeychain && settingsReadError == nil && setup.keychainError == nil && !setup.needsSettingsSave
        state.profileReady = !settings.profiles.isEmpty
        state.locationRequired = true
        state.locationChecked = observer.locationAccessChecked
        state.locationGranted = observer.locationAccessChecked && !observer.locationPermissionMissing
        state.serviceReady = serviceAvailable
        state.serviceChecked = setup.serviceChecked
        state.serviceInstalling = setup.installingService
        state.serviceMessage = setup.serviceMessage
        state.notifications = setup.notifications
        state.notificationsSkipped = UserDefaults.standard.bool(forKey:"setup.notificationsSkipped")
        state.pendingImports = profileImports.count
        return state
    }
    func auditSetup(force: Bool = false) {
        guard !liveNetworkTest else { return }
        if preview { advanceAutomaticSetup(); return }
        if !setup.notificationReadInFlight && (force || Date().timeIntervalSince(setup.lastRead) >= 15) {
            setup.lastRead = Date(); setup.notificationReadInFlight = true
            UNUserNotificationCenter.current().getNotificationSettings { [weak self] value in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.setup.notificationReadInFlight = false
                    switch value.authorizationStatus {
                    case .notDetermined: self.setup.notifications = .notRequested
                    case .denied: self.setup.notifications = .denied
                    default: self.setup.notifications = .allowed
                    }
                    self.presentSetupIfNeeded(); self.advanceAutomaticSetup()
                }
            }
        }
        presentSetupIfNeeded(); advanceAutomaticSetup()
    }
    func advanceAutomaticSetup() {
        guard !liveNetworkTest, !preview || setupTestActionRunner != nil else { return }
        let state = setupReadiness
        let canRequest = preview ? setupTestCanRequestLocation : observer.canRequestLocationPermission
        guard let action = setup.automation.next(state,busy:busy,modal:NSApp.modalWindow != nil,canRequestLocation:canRequest) else { return }
        // Reserve and start together on the main thread. A later status poll
        // cannot consume the one-shot action before the installer starts.
        if preview, let run = setupTestActionRunner { run(action); return }
        switch action {
        case .location: observer.requestInitialPermission()
        case .service: installService(automatic:true)
        case .notifications: performSetupAction(.notifications)
        }
    }
    func presentSetupIfNeeded(explicit: Bool = false) {
        guard (!preview || setupTestReadiness != nil), !liveNetworkTest, window != nil else { return }
        if explicit { setup.automation.deferred = false; setup.reviewing = true }
        let state = setupReadiness
        let newBuild = UserDefaults.standard.string(forKey:"setup.completedBuild") != setupBuild
        let visible = setup.window?.isVisible == true
        // Rearm detection after recovery, so a later revocation of the same
        // permission is not mistaken for an already-dismissed warning.
        if state.stage == .ready && !setup.reviewing {
            if !preview { UserDefaults.standard.set(setupBuild,forKey:"setup.completedBuild") }
            setup.window?.orderOut(nil); setup.lastPresented = ""; return
        }
        let present = explicit || (!setup.automation.deferred && !busy && NSApp.modalWindow == nil && setup.lastPresented != state.signature && SetupAssistantState.shouldOffer(state,newBuild:newBuild,loadingKeychain:setup.loadingKeychain,serviceChecked:setup.serviceChecked,keychainPromptNeeded:setup.keychainPromptNeeded))
        guard visible || present else { return }
        if setup.window == nil {
            let panel = NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:620),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            panel.title = "AutoTurn / Разрешения и настройка"; panel.isReleasedWhenClosed = false
            panel.appearance = NSAppearance(named:.darkAqua); panel.backgroundColor = Palette.bg; panel.center(); panel.delegate = self
            setup.window = panel
        }
        let revision = state.signature + "\(setup.loadingKeychain)"
        if setup.rendered != revision {
            setup.window?.contentView = SetupAssistantView.make(state,loading:setup.loadingKeychain,version:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "",action:{ [weak self] in self?.performSetupAction($0) },files:{ [weak self] in self?.acceptProfileDrop($0) ?? false })
            setup.rendered = revision
        }
        setup.lastPresented = state.signature
        if present && !visible { setup.window?.makeKeyAndOrderFront(nil); setup.window?.displayIfNeeded(); NSApp.activate(ignoringOtherApps:true) }
    }
    func performSetupAction(_ action: SetupAction) {
        switch action {
        case .keychain:
            if settingsReadError != nil { retrySettings() }
            else if setup.needsSettingsSave { persistAndConfigure() }
            else { do { _ = try Storage.load(); setup.keychainError = nil } catch { setup.keychainError = error.localizedDescription } }
        case .profile: importProfile()
        case .location: observer.requestPermission()
        case .service: installService()
        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options:[.alert]) { [weak self] _,_ in DispatchQueue.main.async { self?.auditSetup(force:true) } }
        case .notificationSettings: NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
        case .skipNotifications: UserDefaults.standard.set(true,forKey:"setup.notificationsSkipped")
        case .refresh: observer.checkLocationAccess(); observer.report(); refresh()
        case .finish:
            guard setupReadiness.stage == .ready else { auditSetup(force:true); return }
            if !preview { UserDefaults.standard.set(setupBuild,forKey:"setup.completedBuild") }
            setup.reviewing = false; setup.window?.orderOut(nil)
        case .later: setup.reviewing = false; setup.automation.deferred = true; setup.window?.orderOut(nil)
        }
        auditSetup()
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        guard !preview, !setup.loadingKeychain else { return }
        observer.report(); refresh(); auditSetup(force:true)
        guard !setup.accessReadInFlight else { return }
        setup.accessReadInFlight = true
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let allowed = Storage.canReadWithoutPrompt()
            DispatchQueue.main.async {
                guard let self = self else { return }; self.setup.accessReadInFlight = false
                if !allowed { self.setup.keychainError = "Нет доступа к сохранённым профилям. Разблокируй Связку ключей или разреши AutoTurn доступ." }
                else if self.settingsReadError != nil { self.retrySettings() }
                else { self.setup.keychainError = nil }
                self.auditSetup()
            }
        }
    }
}
