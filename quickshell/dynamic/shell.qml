import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    // =====================================================
    //  PENGATURAN (ubah di sini)
    // =====================================================
    readonly property color cBg:      "#171723"   // window#waybar background
    readonly property color cText:    "#B9D4E3"
    readonly property color cAccent:  "#A6CAE4"   // garis workspace aktif
    readonly property color cHover:   "#1e1e1e"
    readonly property color cUrgent:  "#5b4950"
    readonly property color cItem:    "#222233"   // kotak item di dalam panel
    readonly property int   barHeight: 28

    // DnD: true = notifikasi "critical" (mis. baterai kritis) tetap muncul sebagai toast
    readonly property bool dndAllowCritical: false

    // Suara notifikasi: taruh file suara-mu di folder sounds/ (wav / ogg / flac / mp3)
    // Diputar lewat pw-play (PipeWire), cadangan paplay lalu ffplay.
    readonly property string soundDir:   "/home/nanoarch/.config/quickshell/dynamic/sounds/"
    readonly property string notifSound: soundDir + "notify.wav"    // notifikasi biasa
    readonly property string timerSound: soundDir + "timer.wav"     // timer selesai
    // Suara khusus per aplikasi (nama = yang tampil di panel notifikasi).
    // "" = app itu tanpa suara. Contoh isi:
    //   "Battery": soundDir + "battery.wav",
    //   "Discord": ""
    readonly property var appSounds: ({ })

    // Ikon (ganti dengan glyph dari config waybar-mu kalau ada yang beda)
    readonly property string icTab:   " /vey "
    readonly property string icWifi:  "󰖩"
    readonly property string icCpu:   "󰻠"
    readonly property string icMem:   "󰍛"
    readonly property string icPower: "⏻"
    readonly property string icBell:  "󰂚"
    readonly property string icBellOff: "󰂛"      // ikon bell saat DnD aktif
    readonly property string icTimer: "\uDB81\uDD1B"   // ikon timer di bar (nerd font, ganti kalau perlu)
    readonly property string icWsDefault: "○"     // ikon workspace biasa
    readonly property string icWsActive:  "●"     // ikon workspace aktif
    readonly property var    icWsCustom: ({ "1": "⚠" })   // ikon khusus per nomor
    readonly property var batIcons: ["󰂎","󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"]
    readonly property var volIcons: ["󰕿","󰖀","󰕾"]

    // Island & musik (rmpc = klien MPD, datanya diambil lewat `mpc`)
    readonly property string scriptDir: "/home/nanoarch/.config/quickshell/dynamic/"
    readonly property string musicDir:  ""    // kosong = baca dari mpd.conf. Contoh: "/home/nanoarch/Music"
    readonly property string lyricsDir: ""    // kosong = sama dengan musicDir (file .lrc di samping lagu)
    readonly property string icPlay:  "\uDB81\uDC0A"          // ikon play  (nerd font)
    readonly property string icPause: "\uDB80\uDFE4"          // ikon pause (nerd font)
    readonly property string icModeIsland: "◖◗"                // tombol di bar statis: pindah ke dynamic island
    readonly property string icModeBar:    "▬▬"                // tombol di dynamic island: pindah ke bar statis

    // =====================================================
    //  DATA (state yang dipakai bar)
    // =====================================================
    property int    selMask: 0          // workspace (tag) aktif
    property int    urgMask: 0          // workspace urgent
    property string essid: ""           // nama wifi
    property real   cpuUsage: 0
    property real   memUsedGb: 0
    property real   prevIdle: 0
    property real   prevTotal: 0
    property string catFrame: "A"       // frame huruf dari catloop.sh
    property bool   showDate: false     // klik kanan jam = ganti jam/tanggal
    property bool   soundOn: true       // suara notifikasi aktif/tidak

    // kalender (bulan yang sedang ditampilkan di panel jam)
    property int    calYear:  new Date().getFullYear()
    property int    calMonth: new Date().getMonth()

    // timer hitung mundur
    property int    timerTotal: 300     // durasi yang dipilih (detik)
    property int    timerLeft: 300      // sisa waktu (detik)
    property bool   timerRunning: false
    property real   timerEnd: 0         // waktu selesai (epoch ms), supaya akurat

    // jadwal per tanggal
    property string clockTab: "timer"   // tab bawah panel jam: "timer" / "schedule"
    property string selDate: ""         // tanggal terpilih (yyyy-MM-dd)
    property var    schedules: ({})     // { "2026-11-08": ["rapat 10:00", "beli kopi"] }
    property string lastRemindDay: ""   // hari terakhir yang sudah diingatkan

    // data toast notifikasi
    property bool   toastOpen: false
    property string toastSummary: ""
    property string toastBody: ""

    // ---------- Workspace (tag) mangowm lewat mmsg (format JSON baru) ----------
    readonly property string monitorName: "eDP-1"   // ganti kalau nama monitormu beda

    function parseTags(line) {
        if (line.trim() === "") return
        try {
            const o = JSON.parse(line)
            if (!o.tags) return
            let sel = 0, urg = 0
            o.tags.forEach(t => {
                if (t.is_active) sel |= (1 << (t.index - 1))   // tag 1 = bit 0, dst.
                if (t.is_urgent) urg |= (1 << (t.index - 1))
            })
            selMask = sel
            urgMask = urg
        } catch (e) { /* baris bukan JSON valid: abaikan */ }
    }
    Process {                                   // watch: kirim state awal + tiap ada perubahan
        command: ["mmsg", "watch", "tags", root.monitorName]
        running: true
        stdout: SplitParser { onRead: line => root.parseTags(line) }
    }

    // ---------- Jaringan: nmcli ----------
    ListModel { id: wifiModel }

    Process {                                   // nama wifi yang sedang aktif
        id: netStatus
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let name = ""
                text.split("\n").forEach(l => { if (l.startsWith("yes:")) name = l.substring(4) })
                root.essid = name
            }
        }
    }
    Process {                                   // "nmcli monitor" = keluar baris tiap jaringan berubah
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser { onRead: () => { if (!netStatus.running) netStatus.running = true } }
    }
    Process {                                   // daftar wifi untuk panel
        id: scan
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL", "dev", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                wifiModel.clear()
                text.split("\n").forEach(l => {
                    const p = l.split(":")
                    if (p.length < 3 || p[1] === "") return
                    wifiModel.append({ active: p[0] === "*", ssid: p[1], signal: parseInt(p[2]) })
                })
            }
        }
    }
    Process {                                   // connect ke wifi yang sudah tersimpan
        id: connectProc
        property string ssid: ""
        command: ["nmcli", "dev", "wifi", "connect", ssid]
    }
    Component.onCompleted: { netStatus.running = true; loadEq(); loadDnd(); loadSound(); loadSchedule(); loadMode(); islandFlash() }

    // ---------- CPU & RAM: baca /proc tiap 1 detik ----------
    FileView { id: statFile; path: "/proc/stat" }
    FileView { id: memFile;  path: "/proc/meminfo" }
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            statFile.reload(); memFile.reload()

            // CPU: pemakaian = 1 - (selisih idle / selisih total)
            const f = statFile.text().split("\n")[0].trim().split(/\s+/).slice(1, 9).map(Number)
            const idle = f[3] + f[4]
            const total = f.reduce((a, b) => a + b, 0)
            const dTotal = total - root.prevTotal
            root.cpuUsage = dTotal > 0 ? (1 - (idle - root.prevIdle) / dTotal) * 100 : 0
            root.prevIdle = idle
            root.prevTotal = total

            // RAM terpakai = MemTotal - MemAvailable (kB -> GB)
            const m = memFile.text()
            const mt = parseInt(m.match(/MemTotal:\s+(\d+)/)[1])
            const ma = parseInt(m.match(/MemAvailable:\s+(\d+)/)[1])
            root.memUsedGb = (mt - ma) / 1048576
        }
    }

    // ---------- Kucing CPU: baca output catloop.sh baris per baris ----------
    Process {
        command: ["/home/nanoarch/.config/waybar/scripts/catloop.sh"]
        running: true
        stdout: SplitParser { onRead: line => { if (line.length > 0) root.catFrame = line.trim() } }
    }

    // ---------- Volume (pengganti wireplumber module) ----------
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property real  vol:   (sink && sink.audio) ? sink.audio.volume : 0
    readonly property bool  muted: (sink && sink.audio) ? sink.audio.muted : false

    // ---------- Baterai ----------
    readonly property var bat: UPower.displayDevice

    // ---------- Peringatan baterai (makin lemah makin heboh) ----------
    // Urutan HARUS dari level tertinggi ke terendah.
    // Tiap pesan = [judul, isi]. Isi boleh "" kalau cuma judul.
    readonly property var batWarnings: [
        { level: 20, lines: [
            ["Battery 20%", "need a charge"]
        ]},
        { level: 10, lines: [
            ["yo", ""],
            ["I think u need", ""],
            ["to charge ur device", ""],
            ["not gonna lie", ""]
        ]},
        { level: 5, lines: [
            ["YOO", ""],
            ["Go grab my charger", ""],
            ["Im gonna die", ""],
            ["fuck", ""],
            ["bruh i hate you", ""]
        ]},
        { level: 3, lines: [
            ["man my last word is", ""],
            ["just charge me mother FUCKK", ""]
        ]}
    ]
    property int batNextStage: 0        // index peringatan berikutnya yang belum dikirim
    property var msgQueue: []           // antrean pesan yang menunggu dikirim

    // masukkan pesan ke antrean, lalu timer mengirim satu per satu
    function spam(lines) {
        msgQueue = msgQueue.concat(lines)
        if (!spamTimer.running) spamTimer.start()
    }

    // dipanggil tiap 5 detik: cek persen baterai & kirim peringatan kalau perlu
    function checkBattery() {
        if (!bat || !bat.isPresent || bat.percentage <= 0) return   // UPower belum siap
        const pct = Math.round(bat.percentage * 100)
        const s = bat.state
        const charging = s === UPowerDeviceState.Charging
                      || s === UPowerDeviceState.FullyCharged
                      || s === UPowerDeviceState.PendingCharge

        if (charging) {
            // lagi dicas: tandai level yang sudah dilewati sebagai "sudah dikirim",
            // level di bawah persen sekarang dianggap belum (boleh kirim lagi nanti)
            let next = batWarnings.length
            for (let i = 0; i < batWarnings.length; i++) {
                if (batWarnings[i].level < pct) { next = i; break }
            }
            batNextStage = next
            return
        }

        // tidak dicas: cari peringatan terparah yang baru saja terlewati
        let hit = -1
        for (let i = batNextStage; i < batWarnings.length; i++)
            if (pct <= batWarnings[i].level) hit = i
        if (hit >= 0) {
            batNextStage = hit + 1                  // jangan kirim level ini lagi
            spam(batWarnings[hit].lines)
        }
    }

    Timer {                                         // cek baterai berkala
        interval: 5000; running: true; repeat: true
        onTriggered: root.checkBattery()
    }
    Timer {                                         // kirim 1 pesan tiap 1.1 detik
        id: spamTimer
        interval: 1500; repeat: true; triggeredOnStart: true
        onTriggered: {
            if (root.msgQueue.length === 0) { stop(); return }
            const m = root.msgQueue[0]
            root.msgQueue = root.msgQueue.slice(1)
            // -u critical = garis merah di panel & bisa tembus DnD (lihat dndAllowCritical)
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Battery", m[0], m[1]])
        }
    }

    // ---------- Jam ----------
    SystemClock { id: clock; precision: SystemClock.Minutes }
    // jam dengan detik: hanya aktif saat panel jam terbuka (hemat CPU)
    SystemClock { id: clockSec; precision: SystemClock.Seconds; enabled: win.page === "clock" }

    // ---------- Suara ----------
    function playSound(file) {
        if (!file || file === "") return
        // $1 = file; kalau file tidak ada, diam saja
        Quickshell.execDetached(["sh", "-c",
            'f="$1"; [ -f "$f" ] || exit 0; pw-play "$f" 2>/dev/null || paplay "$f" 2>/dev/null || ffplay -nodisp -autoexit -loglevel quiet "$f" 2>/dev/null',
            "sh", file])
    }
    function playNotifSound(appName) {
        if (!soundOn || appName === "Timer") return        // timer punya suara sendiri
        const f = appSounds[appName] !== undefined ? appSounds[appName] : notifSound
        playSound(f)
    }

    // ---------- Kalender & jadwal ----------
    function dayKey(d) { return Qt.formatDate(d, "yyyy-MM-dd") }
    function fmtKey(k) {
        const p = k.split("-")
        return Qt.formatDate(new Date(+p[0], +p[1] - 1, +p[2]), "d MMM yyyy")
    }
    function itemsFor(k) { return schedules[k] || [] }

    // 42 sel (6 minggu), minggu mulai hari Senin
    function buildCal(y, m, now, sched) {
        const offset = (new Date(y, m, 1).getDay() + 6) % 7
        const todayKey = dayKey(now)
        const out = []
        for (let i = 0; i < 42; i++) {
            const d = new Date(y, m, 1 - offset + i)
            const k = dayKey(d)
            out.push({
                day: d.getDate(), year: d.getFullYear(), month: d.getMonth(), key: k,
                inMonth: d.getMonth() === m,
                weekend: d.getDay() === 0 || d.getDay() === 6,
                today: k === todayKey,
                has: (sched[k] || []).length > 0
            })
        }
        return out
    }
    readonly property var calCells: buildCal(calYear, calMonth, clock.date, schedules)
    function calShift(n) {
        const d = new Date(calYear, calMonth + n, 1)
        calYear = d.getFullYear()
        calMonth = d.getMonth()
    }
    function calToday() {
        const d = new Date()
        calYear = d.getFullYear()
        calMonth = d.getMonth()
        selDate = dayKey(d)
    }

    // jadwal disimpan di ~/.local/state/dynamic-schedule.json
    FileView { id: schedState; path: "/home/nanoarch/.local/state/dynamic-schedule.json"; blockLoading: true }
    function loadSchedule() {
        selDate = dayKey(new Date())
        try { const t = schedState.text().trim(); if (t !== "") schedules = JSON.parse(t) } catch (e) { /* belum ada file */ }
    }
    function saveSchedule() {
        // JSON dikirim sebagai argumen ($1) supaya karakter apa pun aman
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p "$HOME/.local/state"; printf %s "$1" > "$HOME/.local/state/dynamic-schedule.json"',
            "sh", JSON.stringify(schedules)])
    }
    function schedAdd(key, text) {
        text = text.trim()
        if (key === "" || text === "") return
        const m = Object.assign({}, schedules)
        m[key] = (m[key] || []).concat([text])
        schedules = m                               // assign objek baru supaya UI ikut update
        saveSchedule()
    }
    function schedRemove(key, i) {
        const m = Object.assign({}, schedules)
        const a = (m[key] || []).slice()
        a.splice(i, 1)
        if (a.length === 0) delete m[key]
        else m[key] = a
        schedules = m
        saveSchedule()
    }
    // ingatkan jadwal hari ini (sekali per hari: saat bar start & saat ganti hari)
    function checkToday() {
        const k = dayKey(new Date())
        if (k === lastRemindDay) return
        lastRemindDay = k
        const items = itemsFor(k)
        if (items.length > 0)
            Quickshell.execDetached(["notify-send", "-a", "Schedule",
                                     "Schedule today (" + items.length + ")", items.join("\n")])
    }
    Connections { target: clock; function onDateChanged() { root.checkToday() } }
    Timer { interval: 3000; running: true; onTriggered: root.checkToday() }   // tunggu notif server siap

    // ---------- Timer ----------
    function fmtTime(s) {
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60
        const p = n => (n < 10 ? "0" : "") + n
        return (h > 0 ? h + ":" : "") + p(m) + ":" + p(r)
    }
    // "25" = 25 menit, "5:30" = 5 menit 30 detik, "1:30:00" = 1 jam 30 menit
    function parseDuration(t) {
        const p = t.split(":").filter(x => x !== "").map(Number)
        if (p.length === 0 || p.some(isNaN)) return 0
        if (p.length === 1) return p[0] * 60
        if (p.length === 2) return p[0] * 60 + p[1]
        return p[0] * 3600 + p[1] * 60 + p[2]
    }
    function timerSet(sec) {                      // pilih durasi baru (menghentikan timer)
        timerRunning = false
        timerTotal = Math.max(0, Math.min(86399, sec))
        timerLeft = timerTotal
    }
    function timerAdd(sec) {                      // tambah / kurangi waktu
        if (timerRunning) {
            timerEnd += sec * 1000
            timerTotal = Math.max(1, timerTotal + sec)
            timerLeft = Math.max(1, Math.ceil((timerEnd - Date.now()) / 1000))
        } else {
            timerSet(timerTotal + sec)
        }
    }
    function timerToggle() {                      // start / pause
        if (timerRunning) {
            timerLeft = Math.max(0, Math.ceil((timerEnd - Date.now()) / 1000))
            timerRunning = false
            return
        }
        if (timerLeft <= 0) timerLeft = timerTotal
        if (timerLeft <= 0) return
        timerEnd = Date.now() + timerLeft * 1000
        timerRunning = true
    }
    function timerReset() { timerRunning = false; timerLeft = timerTotal }
    function timerFinished() {
        timerRunning = false
        timerLeft = timerTotal                    // siap dipakai lagi
        playSound(timerSound)                     // suara timer selalu bunyi (tidak ikut tombol Sound)
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Timer",
                                 "Timer selesai", fmtTime(timerTotal) + " sudah habis"])
    }
    Timer {
        interval: 250; repeat: true
        running: root.timerRunning
        onTriggered: {
            const left = Math.ceil((root.timerEnd - Date.now()) / 1000)
            if (left <= 0) root.timerFinished()
            else root.timerLeft = left
        }
    }

    // ---------- Volume & Equalizer (PipeWire filter-chain, lihat eq.conf) ----------
    readonly property var eqFreqs: ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    readonly property var eqPresets: ({
        "Flat":   [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Bass":   [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
        "Vocal":  [-2, -1, 0, 1, 3, 4, 3, 1, 0, -1],
        "Treble": [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]
    })
    property var eqGains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]    // gain tiap band (dB)

    function setVolume(v) {
        if (sink && sink.audio) sink.audio.volume = Math.max(0, Math.min(1, v))
    }
    function fmtGain(g) { return (g > 0 ? "+" : "") + (g % 1 === 0 ? g.toFixed(0) : g.toFixed(1)) }

    // kirim semua gain ke PipeWire lewat eq-set.sh
    function applyEq() {
        const args = ["/home/nanoarch/.config/quickshell/dynamic/eq-set.sh"]
        for (let i = 0; i < eqGains.length; i++) args.push((i + 1) + "=" + eqGains[i].toFixed(1))
        Quickshell.execDetached(args)
    }
    function setBand(i, v) {
        const g = eqGains.slice()
        g[i] = Math.round(v * 2) / 2          // dibulatkan ke 0.5 dB
        eqGains = g                           // assign array baru supaya slider ikut update
        eqTimer.restart()                     // tunda 80ms biar tidak spam pw-cli saat digeser
    }
    function loadPreset(name) { eqGains = eqPresets[name].slice(); applyEq() }

    // baca nilai terakhir yang disimpan eq-set.sh (format: "1=3.0 2=0.0 ...")
    function loadEq() {
        try {
            const t = eqState.text().trim()
            if (t === "") return
            const g = eqGains.slice()
            t.split(/\s+/).forEach(pair => {
                const kv = pair.split("=")
                const idx = parseInt(kv[0]) - 1
                if (idx >= 0 && idx < g.length) g[idx] = parseFloat(kv[1])
            })
            eqGains = g
            applyEq()
        } catch (e) { /* file belum ada: abaikan */ }
    }
    Timer { id: eqTimer; interval: 80; onTriggered: root.applyEq() }
    FileView { id: eqState; path: "/home/nanoarch/.local/state/dynamic-eq"; blockLoading: true }

    // ---------- Notifikasi (menggantikan mako/dunst) ----------
    NotificationServer {
        id: notifs
        keepOnReload: true
        bodySupported: true
        onNotification: n => {
            n.tracked = true                       // SEMUA notifikasi masuk ke list (dari semua aplikasi)
            const critical = n.urgency === NotificationUrgency.Critical
            // DnD aktif: simpan di list saja, jangan tampilkan toast
            if (root.dnd && !(root.dndAllowCritical && critical)) return
            root.playNotifSound(n.appName)         // suara custom (lihat pengaturan di atas)
            root.toastSummary = n.summary
            root.toastBody = n.body
            root.toastOpen = true
            toastTimer.restart()
        }
    }
    Timer { id: toastTimer; interval: 5000; onTriggered: root.toastOpen = false }

    // ---------- Do Not Disturb ----------
    property bool dnd: false
    readonly property int notifCount: notifs.trackedNotifications.values.length

    FileView { id: dndState; path: "/home/nanoarch/.local/state/dynamic-dnd"; blockLoading: true }
    function loadDnd() {
        try { dnd = dndState.text().trim() === "1" } catch (e) { /* belum ada file: biarkan false */ }
    }
    function toggleDnd() {
        dnd = !dnd
        if (dnd) { toastOpen = false; toastTimer.stop() }     // tutup toast yang sedang tampil
        // simpan supaya DnD ingat setelah quickshell di-restart
        Quickshell.execDetached(["sh", "-c", "mkdir -p ~/.local/state && echo " + (dnd ? 1 : 0) + " > ~/.local/state/dynamic-dnd"])
    }
    // ---------- Suara notifikasi on/off (disimpan) ----------
    FileView { id: soundState; path: "/home/nanoarch/.local/state/dynamic-sound"; blockLoading: true }
    function loadSound() {
        try { const t = soundState.text().trim(); if (t !== "") soundOn = t === "1" } catch (e) { /* belum ada file */ }
    }
    function toggleSound() {
        soundOn = !soundOn
        if (soundOn) playSound(notifSound)                    // contoh suara saat dinyalakan
        Quickshell.execDetached(["sh", "-c", "mkdir -p ~/.local/state && echo " + (soundOn ? 1 : 0) + " > ~/.local/state/dynamic-sound"])
    }
    function clearAll() {
        notifs.trackedNotifications.values.slice().forEach(n => n.dismiss())
    }

    // supaya bisa di-toggle dari keybind:  quickshell ipc -c dynamic call notif toggleDnd
    IpcHandler {
        target: "notif"
        function toggleDnd(): void { root.toggleDnd() }
        function toggleSound(): void { root.toggleSound() }
    }

    // keybind timer:  quickshell ipc -c dynamic call timer start 300   (5 menit)
    IpcHandler {
        target: "timer"
        function start(seconds: int): void { root.timerSet(seconds); root.timerToggle() }
        function toggle(): void { root.timerToggle() }
        function reset(): void { root.timerReset() }
    }

    // ---------- Rofi (dibuka dari tombol UP) ----------
    // dijalankan sebagai Process supaya bar tahu kapan rofi terbuka / tertutup
    Process {
        id: rofiProc
        command: ["rofi", "-show", "drun"]
    }

    // ---------- Mode tampilan: "bar" (biasa) atau "island" (pil dinamis) ----------
    property string uiMode: "island"     // "island" (dynamic, auto-hide) atau "bar" (statis, selalu tampil) - dipilih lewat tombol & disimpan
    readonly property bool island: uiMode === "island"
    property int    islandPage: 0        // -2 musik | -1 workspace+UP+baterai+media | 0 tanggal | 1 cat/net/cpu/ram/vol/notif/power
    property real   swipeAcc: 0
    onIslandPageChanged: {
        if (islandPage === -2) { win.page = ""; refreshStatus(); fetchQueue() }
    }
    FileView { id: modeState; path: "/home/nanoarch/.local/state/dynamic-mode"; blockLoading: true }
    function loadMode() {
        try { const t = modeState.text().trim(); if (t === "island" || t === "bar") uiMode = t } catch (e) { /* belum ada file */ }
    }
    function setMode(m) {
        uiMode = m
        islandPage = 0
        win.page = ""
        if (m === "island") islandFlash()          // munculkan sebentar setelah pindah
        Quickshell.execDetached(["sh", "-c", "mkdir -p ~/.local/state && echo " + m + " > ~/.local/state/dynamic-mode"])
    }
    // munculkan island sebentar (dipakai saat geser lewat keybind & saat bar baru start)
    function islandFlash() { win.islandReveal = true; hideTimer.restart() }
    function islandGo(d) { islandPage = Math.max(-2, Math.min(1, islandPage + d)); islandFlash() }

    // keybind:  quickshell ipc -c dynamic call island next | prev | goto 0 | toggleMode
    IpcHandler {
        target: "island"
        function next(): void { root.islandGo(1) }
        function prev(): void { root.islandGo(-1) }
        function goto(page: int): void { root.islandPage = Math.max(-2, Math.min(1, page)); root.islandFlash() }
        function toggleMode(): void { root.setMode(root.island ? "bar" : "island") }
    }

    // ---------- Musik: rmpc / MPD lewat mpc ----------
    property string mpdState: ""         // "play" / "pause" / "stop" / "" (mpd tidak jalan)
    property string mpdTitle: ""
    property string mpdArtist: ""
    property string mpdAlbum: ""
    property string mpdFile: ""
    property int    mpdPos: 0            // nomor lagu di queue (mulai 1)
    property int    mpdTotal: 0
    property real   mpdBase: 0           // detik berjalan saat status terakhir diambil
    property real   mpdStamp: 0          // epoch ms saat status terakhir diambil
    property real   mpdDuration: 0
    property real   mpdPosNow: 0         // posisi lagu sekarang (diinterpolasi)
    property string artSource: ""
    property var    lrcLines: []         // [{ t: detik, text: "..." }, ...]
    property int    lyricIdx: -1

    function pad(v, n) { return String(v).padStart(n, " ") }      // rata kanan, lebar tetap
    function mpc(args) { Quickshell.execDetached(["mpc"].concat(args)) }
    function parseClock(t) {
        const p = t.split(":").map(Number)
        return p.length === 3 ? p[0] * 3600 + p[1] * 60 + p[2] : p[0] * 60 + p[1]
    }
    function refreshStatus() { if (!mpdStatusProc.running) mpdStatusProc.running = true }
    function fetchQueue()    { if (!mpdQueueProc.running)  mpdQueueProc.running = true }

    function applyStatus(text) {
        const lines = text.split("\n")
        let si = -1
        for (let i = 0; i < lines.length; i++)
            if (/^\[(playing|paused)\]/.test(lines[i])) { si = i; break }
        if (si < 1) {                                        // tidak ada lagu yang dipilih / mpd mati
            mpdState = text.trim() === "" ? "" : "stop"
            mpdTitle = ""; mpdArtist = ""; mpdAlbum = ""; mpdPosNow = 0; mpdDuration = 0
            if (mpdFile !== "") { mpdFile = ""; lrcLines = []; lyricIdx = -1; artSource = "" }
            return
        }
        const m = lines[si].match(/\[(\w+)\]\s+#(\d+)\/(\d+)\s+([\d:]+)\/([\d:]+)/)
        if (!m) return
        const f = lines[si - 1].split("\t")
        mpdState = m[1] === "playing" ? "play" : "pause"
        mpdPos = parseInt(m[2]); mpdTotal = parseInt(m[3])
        mpdBase = parseClock(m[4]); mpdDuration = parseClock(m[5])
        mpdStamp = Date.now(); mpdPosNow = mpdBase
        mpdTitle = f[0] || ""; mpdArtist = f[1] || ""; mpdAlbum = f[2] || ""
        const file = f[3] || ""
        if (file !== mpdFile) {                              // lagu ganti: ambil cover & lirik baru
            mpdFile = file; lrcLines = []; lyricIdx = -1; artSource = ""
            fetchArt(); fetchLyrics()
        }
        updateLyricIdx()
    }

    // ---------- Lirik (.lrc) ----------
    function parseLrc(text) {
        const out = []
        text.split("\n").forEach(line => {
            const re = /\[(\d+):(\d+(?:\.\d+)?)\]/g
            const stamps = []
            let m
            while ((m = re.exec(line)) !== null) stamps.push(+m[1] * 60 + parseFloat(m[2]))
            const txt = line.replace(/\[[^\]]*\]/g, "").trim()
            stamps.forEach(t => out.push({ t: t, text: txt }))
        })
        out.sort((a, b) => a.t - b.t)
        return out
    }
    function updateLyricIdx() {
        let idx = -1
        for (let i = 0; i < lrcLines.length; i++) {
            if (lrcLines[i].t <= mpdPosNow + 0.2) idx = i
            else break
        }
        lyricIdx = idx
    }
    function lyricAt(off) {
        if (lrcLines.length === 0) return off === 0 ? "No lyrics (put a .lrc next to the song)" : ""
        const i = lyricIdx + off
        if (i < 0 || i >= lrcLines.length) return off === 0 ? "♪" : ""
        return lrcLines[i].text !== "" ? lrcLines[i].text : (off === 0 ? "♪" : "")
    }
    property bool lrcPending: false
    function fetchLyrics() {
        if (lrcProc.running) { lrcPending = true; return }
        lrcProc.running = true
    }
    Process {
        id: lrcProc
        command: ["bash", root.scriptDir + "lyrics.sh", root.mpdFile, root.musicDir, root.lyricsDir]
        stdout: StdioCollector { onStreamFinished: { root.lrcLines = root.parseLrc(text); root.updateLyricIdx() } }
        onExited: { if (root.lrcPending) { root.lrcPending = false; root.fetchLyrics() } }
    }

    // ---------- Cover album ----------
    property int  artCounter: 0
    property bool artPending: false
    function fetchArt() {
        if (artProc.running) { artPending = true; return }
        artCounter += 1
        artProc.out = "/tmp/dynamic-art-" + artCounter       // nama unik supaya gambar tidak ter-cache
        artProc.running = true
    }
    Process {
        id: artProc
        property string out: ""
        command: ["bash", root.scriptDir + "art.sh", out, root.mpdFile]
        stdout: StdioCollector { onStreamFinished: root.artSource = text.trim() !== "" ? "file://" + text.trim() : "" }
        onExited: { if (root.artPending) { root.artPending = false; root.fetchArt() } }
    }

    // ---------- Status & queue ----------
    ListModel { id: queueModel }
    Process {
        id: mpdStatusProc
        command: ["mpc", "-f", "[%title%|%file%]\t%artist%\t%album%\t%file%", "status"]
        stdout: StdioCollector { onStreamFinished: root.applyStatus(text) }
    }
    Process {
        id: mpdQueueProc
        command: ["mpc", "-f", "%position%\t%artist%\t[%title%|%file%]", "playlist"]
        stdout: StdioCollector {
            onStreamFinished: {
                queueModel.clear()
                text.split("\n").forEach(l => {
                    if (l === "") return
                    const q = l.split("\t")
                    queueModel.append({ pos: parseInt(q[0]), artist: q[1] || "", title: q[2] || "" })
                })
            }
        }
    }
    Process {                                   // "mpc idleloop" = keluar baris tiap player / queue berubah
        id: mpdIdle
        command: ["mpc", "idleloop", "player", "playlist"]
        running: true
        stdout: SplitParser { onRead: line => { if (line === "playlist") root.fetchQueue(); root.refreshStatus() } }
        onExited: mpdRetry.start()              // mpd belum jalan / putus: coba lagi nanti
    }
    Timer { id: mpdRetry; interval: 5000; onTriggered: { mpdIdle.running = true; root.refreshStatus(); root.fetchQueue() } }
    Timer { interval: 1500; running: true; onTriggered: { root.refreshStatus(); root.fetchQueue() } }   // data awal
    Timer {                                     // sinkron ulang berkala saat lagu jalan
        interval: 5000; repeat: true; running: root.mpdState === "play"
        onTriggered: root.refreshStatus()
    }
    Timer {                                     // gerakkan progress & lirik (hanya saat halaman musik terlihat)
        interval: 500; repeat: true
        running: root.mpdState === "play" && root.island && root.islandPage === -2
        onTriggered: {
            const t = root.mpdBase + (Date.now() - root.mpdStamp) / 1000
            root.mpdPosNow = root.mpdDuration > 0 ? Math.min(root.mpdDuration, t) : t
            root.updateLyricIdx()
        }
    }

    // =====================================================
    //  WINDOW
    // =====================================================
    PanelWindow {
        id: win
        anchors { top: true; left: true; right: true }
        implicitHeight: 600                  // ruang maksimum untuk animasi panel
        exclusiveZone: root.island ? 0 : root.barHeight   // island melayang (tidak makan ruang), bar biasa makan ruang
        color: "transparent"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand   // perlu supaya bisa mengetik durasi timer

        // hanya bar, panel, dan toast yang menerima klik
        mask: Region {
            item: bar
            Region { item: panel }
            Region { item: toast }
            Region { item: trigger }
        }

        property string page: ""             // "", "wifi", "notif", "audio", atau "clock"
        onPageChanged: {
            if (page === "wifi") scan.running = true
            if (page === "clock") root.calToday()     // selalu buka di bulan ini
        }

        // ================= AUTO-HIDE ISLAND =================
        // island tersembunyi di atas layar; muncul saat kursor dekat tengah-atas,
        // tetap tampil selama kursor di island / panel, atau panel sedang terbuka.
        property bool islandReveal: false
        // halaman musik + lagu aktif: island tidak sembunyi, tapi mengecil jadi pil kecil berisi lirik
        readonly property bool songActive: root.mpdState === "play" || root.mpdState === "pause"
        readonly property bool compactActive: root.island && root.islandPage === -2 && songActive
        readonly property bool islandCompact: compactActive && !islandReveal && page === ""
        readonly property bool islandVisible: !root.island || islandReveal || page !== "" || compactActive
        readonly property bool pointerNear: triggerHover.hovered || barHover.hovered || panelHover.hovered
        onPointerNearChanged: {
            if (pointerNear) { hideTimer.stop(); islandReveal = true }
            else hideTimer.restart()
        }
        Timer {
            id: hideTimer
            interval: 900                                   // jeda sebelum island sembunyi lagi (ms)
            onTriggered: { if (!win.pointerNear) win.islandReveal = false; resetPageTimer.restart() }
        }
        Timer {                                             // setelah tersembunyi, kembali ke halaman tanggal
            id: resetPageTimer
            interval: 400
            onTriggered: { if (!win.islandVisible) root.islandPage = 0 }
        }

        // zona pemicu tak terlihat di tengah-atas layar (gerakkan kursor ke sini)
        Item {
            id: trigger
            x: (parent.width - width) / 2
            y: 0
            width: root.island ? 360 : 0                    // lebar zona pemicu
            height: 8                                       // tinggi zona pemicu dari tepi atas
            HoverHandler { id: triggerHover }
        }

        // ================= BAR =================
        Rectangle {
            id: bar
            // bar biasa: selebar layar. island: pil di tengah yang ukurannya mengikuti halaman
            x: (parent.width - width) / 2
            y: !root.island ? 0 : (win.islandVisible ? 6 : -height - 12)   // tersembunyi = di atas layar
            width: root.island ? islandWidth : parent.width
            height: root.island ? islandHeight : root.barHeight
            radius: root.island ? 16 : 0
            clip: root.island
            color: root.cBg
            property bool animReady: false                  // animasi aktif setelah layout awal selesai
            Timer { interval: 800; running: true; onTriggered: bar.animReady = true }
            Behavior on width  { enabled: bar.animReady; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: bar.animReady; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on y      { enabled: bar.animReady; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on radius { enabled: bar.animReady; NumberAnimation { duration: 260 } }

            readonly property real islandHeight: (root.islandPage === -2 && !win.islandCompact) ? 330 : root.barHeight
            readonly property real islandWantedWidth: win.islandCompact ? Math.min(520, Math.max(220, compactText.implicitWidth + 44))
                : root.islandPage === -2 ? 460
                : root.islandPage === -1 ? leftRow.implicitWidth + 40
                : root.islandPage === 1 ? rightRow.implicitWidth + 40
                : Math.max(150, clockText.implicitWidth + 40)
            // dibulatkan ke atas kelipatan 8 px supaya perubahan kecil tidak bikin pil bergetar,
            // dan dibatasi supaya tidak keluar dari layar
            readonly property real islandWidth: Math.max(100, Math.min(parent.width - 24, Math.ceil(islandWantedWidth / 8) * 8))

            // geser pakai scroll mouse / swipe touchpad (di atas bar island)
            MouseArea {
                z: -1
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                enabled: root.island
                onWheel: wheel => {
                    if (swipeCool.running) return
                    const dx = wheel.angleDelta.x, dy = wheel.angleDelta.y
                    root.swipeAcc += Math.abs(dx) > Math.abs(dy) ? dx : dy
                    if (Math.abs(root.swipeAcc) >= 100) {
                        root.islandGo(root.swipeAcc > 0 ? -1 : 1)     // atas / kiri = halaman kiri
                        root.swipeAcc = 0
                        swipeCool.start()
                    }
                    swipeReset.restart()
                }
            }
            Timer { id: swipeCool;  interval: 600 }
            Timer { id: swipeReset; interval: 400; onTriggered: root.swipeAcc = 0 }
            HoverHandler { id: barHover }

            // ----- KIRI: tab, baterai, workspace -----
            RowLayout {
                id: leftRow
                width: implicitWidth
                x: root.island ? Math.round((bar.width - width) / 2) : 0
                y: Math.round((root.barHeight - height) / 2)
                spacing: 3
                readonly property bool shown: !root.island || root.islandPage === -1
                opacity: shown ? 1 : 0
                enabled: shown
                Behavior on opacity { NumberAnimation { duration: 180 } }

                // custom/tab: klik buka rofi
                BarText {
                    text: root.icTab
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {                                   // klik lagi saat rofi terbuka = tutup
                            if (rofiProc.running) Quickshell.execDetached(["pkill", "-x", "rofi"])
                            else rofiProc.running = true
                        }
                    }
                }

                // battery
                BarText {
                    visible: root.bat.isPresent
                    readonly property int pct: Math.round(root.bat.percentage * 100)
                    readonly property string icon: root.batIcons[Math.round(pct / 10)]
                    text: {
                        const s = root.bat.state
                        if (s === UPowerDeviceState.Charging)      return "󰂄 " + pct + "% "
                        if (s === UPowerDeviceState.FullyCharged)  return "󰁹 " + pct + "% "
                        if (s === UPowerDeviceState.PendingCharge) return "󱟦 " + pct + "% "
                        return " " + icon + " "
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: Quickshell.execDetached(["sh", "-c",
                            "notify-send 'sekarang' \"$(cat /sys/class/power_supply/BAT0/capacity)%\""])
                    }
                }

                // workspaces (tag mangowm 1-9)
                RowLayout {
                    spacing: 0
                    Repeater {
                        model: 5
                        delegate: Rectangle {
                            id: ws
                            required property int index
                            readonly property bool isActive: ((root.selMask >> index) & 1) === 1
                            readonly property bool isUrgent: ((root.urgMask >> index) & 1) === 1
                            readonly property string num: String(index + 1)

                            Layout.leftMargin: 2
                            Layout.rightMargin: 2
                            Layout.preferredWidth: label.implicitWidth + 2
                            Layout.preferredHeight: root.barHeight - 6
                            // hover / urgent seperti di style.css
                            color: isUrgent ? root.cUrgent : (area.containsMouse ? root.cHover : "transparent")

                            BarText {
                                id: label
                                anchors.centerIn: parent
                                color: "#A6CAE4"
                                text: ws.num // + " " + (ws.isActive ? root.icWsActive
                                      // : (root.icWsCustom[ws.num] !== undefined ? root.icWsCustom[ws.num]
                                      // : root.icWsDefault)) + " "
                            }
                            // border-bottom: 2px solid untuk workspace aktif
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 2
                                color: root.cAccent
                                visible: ws.isActive
                            }
                            MouseArea {
                                id: area
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: Quickshell.execDetached(["mmsg", "dispatch", "view," + ws.num])
                            }
                        }
                    }
                }

                // media (island): play / pause lagu rmpc kalau mpd sedang jalan
                BarText {
                    visible: root.island && (root.mpdState === "play" || root.mpdState === "pause")
                    text: "  " + (root.mpdState === "play" ? root.icPause : root.icPlay) + " "
                    MouseArea { anchors.fill: parent; onClicked: root.mpc(["toggle"]) }
                }
                BarText {
                    visible: root.island && (root.mpdState === "play" || root.mpdState === "pause")
                    Layout.maximumWidth: 150
                    elide: Text.ElideRight
                    opacity: 0.7
                    text: root.mpdTitle
                }
            }

            // ----- TENGAH: jam (klik kiri = panel kalender+timer, klik kanan = ganti jam/tanggal) -----
            BarText {
                id: clockText
                x: Math.round((bar.width - width) / 2)
                y: Math.round((root.barHeight - height) / 2)
                readonly property bool shown: !root.island || root.islandPage === 0
                opacity: shown ? 1 : 0
                enabled: shown
                Behavior on opacity { NumberAnimation { duration: 180 } }
                font.pixelSize: 14
                text: (root.island ? Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
                                   : Qt.formatDateTime(clock.date, root.showDate ? "dd-MM-yyyy" : "HH:mm"))
                      + (root.timerRunning ? "  " + root.icTimer + " " + root.fmtTime(root.timerLeft) : "") + " "
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) root.showDate = !root.showDate
                        else win.page = (win.page === "clock" ? "" : "clock")
                    }
                }
            }

            // ----- KANAN: cat, network, cpu, memory, volume, notif, power -----
            RowLayout {
                id: rightRow
                width: implicitWidth
                x: root.island ? Math.round((bar.width - width) / 2) : Math.round(bar.width - width)
                y: Math.round((root.barHeight - height) / 2)
                spacing: 3
                readonly property bool shown: !root.island || root.islandPage === 1
                opacity: shown ? 1 : 0
                enabled: shown
                Behavior on opacity { NumberAnimation { duration: 180 } }

                // custom/cpucat
                Text {
                    text: root.catFrame
                    color: "white"
                    font.family: "Waycat"
                    font.pixelSize: 20
                    font.weight: Font.Bold
                    leftPadding: 5
                    rightPadding: 8
                    MouseArea {
                        anchors.fill: parent
			onClicked: Quickshell.execDetached(["quickshell", "-c", "lockscreen", "ipc", "call", "lock", "lock"])
                    }
                }

                // network: klik = buka panel wifi (menyatu dengan bar)
                BarText {
                    text: root.essid !== ""
                          ? "  " + root.icWifi + "  " + root.essid + "  "
                          : "  ⚠ Lost from internet  "
                    MouseArea {
                        anchors.fill: parent
                        onClicked: win.page = (win.page === "wifi" ? "" : "wifi")
                    }
                }

                // cpu
                BarText { text: " " + root.icCpu + " " + root.pad(Math.round(root.cpuUsage), 3) + "% " }

                // memory
                BarText { text: " " + root.icMem + " " + root.pad(root.memUsedGb.toFixed(1), 4) + "G  " }

                // wireplumber (volume): scroll = ubah volume, klik = pavucontrol
                BarText {
                    text: root.muted
                          ? " 󰝟 mute "
                          : " " + root.volIcons[Math.min(2, Math.floor(root.vol * 3))]
                            + " " + root.pad(Math.round(root.vol * 100), 3) + "% "
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) Quickshell.execDetached(["pavucontrol"])
                            else win.page = (win.page === "audio" ? "" : "audio")
                        }
                        onWheel: wheel => {
                            if (!root.sink || !root.sink.audio) return
                            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05
                            root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + step))
                        }
                    }
                }

                // tombol notifikasi: klik kiri = buka panel, klik kanan = DnD on/off
                BarText {
                    text: " " + (root.dnd ? root.icBellOff : root.icBell)
                          + (root.notifCount > 0 ? " " + root.notifCount : "") + " "
                    opacity: root.dnd ? 0.6 : 1
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) root.toggleDnd()
                            else win.page = (win.page === "notif" ? "" : "notif")
                        }
                    }
                }

                // pindah mode: bar statis <-> dynamic island (ada di kedua mode)
                BarText {
                    text: " " + (root.island ? root.icModeBar : root.icModeIsland) + " "
                    MouseArea { anchors.fill: parent; onClicked: root.setMode(root.island ? "bar" : "island") }
                }

                // custom/power
                BarText {
                    text: "  " + root.icPower + "  "
                    MouseArea {
                        anchors.fill: parent
                        onClicked: Quickshell.execDetached(["/home/nanoarch/.config/rofi/powermenumango.sh"])
                    }
                }
            }

            // ----- mode kecil halaman musik: hanya lirik sekarang (judul kalau tidak ada lirik) -----
            BarText {
                id: compactText
                anchors.horizontalCenter: parent.horizontalCenter
                y: (root.barHeight - height) / 2
                width: Math.max(0, parent.width - 36)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: root.cAccent
                opacity: win.islandCompact ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180 } }
                text: root.lrcLines.length > 0 ? root.lyricAt(0)
                      : (root.mpdTitle + (root.mpdArtist !== "" ? "  -  " + root.mpdArtist : ""))
            }

            // ----- halaman musik (island, geser kiri 2x): cover, judul, artis, lirik, queue rmpc -----
            Item {
                id: musicPage
                anchors.fill: parent
                readonly property bool shown: root.island && root.islandPage === -2 && !win.islandCompact
                opacity: shown ? 1 : 0
                visible: opacity > 0.01
                enabled: shown
                Behavior on opacity { NumberAnimation { duration: 180 } }

                BarText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (root.barHeight - height) / 2
                    font.pixelSize: 12
                    opacity: 0.7
                    text: root.mpdState === "" ? "MPD is not running" : "Queue  " + root.mpdPos + "/" + root.mpdTotal
                }

                // cover album
                Rectangle {
                    id: artBox
                    x: 14
                    y: root.barHeight + 2
                    width: 96; height: 96
                    radius: 8
                    color: root.cItem
                    clip: true
                    BarText { anchors.centerIn: parent; font.pixelSize: 30; opacity: 0.35; text: "♪"; visible: artImg.status !== Image.Ready }
                    Image {
                        id: artImg
                        anchors.fill: parent
                        source: root.artSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        visible: status === Image.Ready
                    }
                }

                // judul / artis / album / waktu
                Column {
                    anchors.left: artBox.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.top: artBox.top
                    spacing: 3
                    BarText { width: parent.width; font.pixelSize: 15; elide: Text.ElideRight; text: root.mpdTitle !== "" ? root.mpdTitle : "Nothing playing" }
                    BarText { width: parent.width; font.pixelSize: 12; opacity: 0.75; elide: Text.ElideRight; text: root.mpdArtist }
                    BarText { width: parent.width; font.pixelSize: 11; opacity: 0.5; elide: Text.ElideRight; text: root.mpdAlbum }
                    BarText { font.pixelSize: 11; opacity: 0.7; text: root.fmtTime(Math.floor(root.mpdPosNow)) + " / " + root.fmtTime(Math.floor(root.mpdDuration)) }
                }

                // kontrol: prev / play-pause / next
                Row {
                    anchors.left: artBox.right
                    anchors.leftMargin: 12
                    anchors.bottom: artBox.bottom
                    spacing: 6
                    Repeater {
                        model: ["prev", "toggle", "next"]
                        delegate: Rectangle {
                            id: ctl
                            required property string modelData
                            width: 38; height: 24; radius: 8
                            color: ctlArea.containsMouse ? root.cHover : root.cItem
                            BarText {
                                anchors.centerIn: parent
                                text: ctl.modelData === "toggle" ? (root.mpdState === "play" ? root.icPause : root.icPlay)
                                      : (ctl.modelData === "prev" ? "«" : "»")
                            }
                            MouseArea { id: ctlArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.mpc([ctl.modelData]) }
                        }
                    }
                }

                // progress (klik = lompat)
                Rectangle {
                    id: pBar
                    x: 14
                    y: artBox.y + artBox.height + 8
                    width: parent.width - 28
                    height: 3
                    radius: 2
                    color: root.cItem
                    Rectangle {
                        height: parent.height; radius: 2
                        color: root.cAccent
                        width: root.mpdDuration > 0 ? parent.width * Math.min(1, root.mpdPosNow / root.mpdDuration) : 0
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.topMargin: -6
                        anchors.bottomMargin: -6
                        onClicked: mouse => root.mpc(["seek", Math.round(mouse.x / width * 100) + "%"])
                    }
                }

                // lirik: baris sebelumnya / sekarang / berikutnya
                Column {
                    id: lyricsCol
                    x: 14
                    y: pBar.y + 12
                    width: parent.width - 28
                    spacing: 2
                    BarText { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; font.pixelSize: 12; opacity: 0.4; text: root.lyricAt(-1) }
                    BarText { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; font.pixelSize: 14; color: root.cAccent; text: root.lyricAt(0) }
                    BarText { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; font.pixelSize: 12; opacity: 0.4; text: root.lyricAt(1) }
                }

                // queue rmpc (klik lagu = putar)
                ListView {
                    id: queueList
                    x: 14
                    y: lyricsCol.y + lyricsCol.height + 8
                    width: parent.width - 28
                    height: parent.height - y - 12
                    spacing: 2
                    clip: true
                    model: queueModel
                    delegate: Rectangle {
                        id: qRow
                        required property int pos
                        required property string artist
                        required property string title
                        readonly property bool cur: qRow.pos === root.mpdPos
                        width: ListView.view.width
                        height: 22
                        radius: 6
                        color: cur ? root.cItem : (qRowArea.containsMouse ? root.cHover : "transparent")
                        BarText {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            color: qRow.cur ? root.cAccent : root.cText
                            text: qRow.pos + ".  " + (qRow.artist !== "" ? qRow.artist + " - " : "") + qRow.title
                        }
                        MouseArea { id: qRowArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.mpc(["play", String(qRow.pos)]) }
                    }
                }
                Connections {                                   // scroll queue ke lagu yang sedang diputar
                    target: root
                    function onMpdPosChanged() { if (musicPage.shown) queueList.positionViewAtIndex(Math.max(0, root.mpdPos - 1), ListView.Contain) }
                }
                onShownChanged: if (shown) queueList.positionViewAtIndex(Math.max(0, root.mpdPos - 1), ListView.Contain)
            }
        }

        // ================= PANEL (wifi / notifikasi) =================
        Rectangle {
            id: panel
            x: root.island ? (parent.width - width) / 2 : parent.width - width
            anchors.top: bar.bottom
            anchors.topMargin: root.island ? 8 : 0
            width: 360
            height: win.page === "wifi" ? 300
                  : win.page === "notif" ? 420
                  : win.page === "audio" ? 370
                  : win.page === "clock" ? 510 : 0
            color: root.cBg                    // warna sama dengan bar = menyatu
            clip: true
            bottomLeftRadius: 16
            bottomRightRadius: root.island ? 16 : 0
            topLeftRadius: root.island ? 16 : 0
            topRightRadius: root.island ? 16 : 0
            HoverHandler { id: panelHover }
            Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

            // daftar wifi
            ListView {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6
                visible: win.page === "wifi"
                model: wifiModel
                delegate: Rectangle {
                    required property string ssid
                    required property int signal
                    required property bool active
                    width: ListView.view.width
                    height: 34
                    radius: 8
                    color: active ? root.cHover : root.cItem
                    BarText { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: ssid }
                    BarText { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: signal + "%"; opacity: 0.6 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { connectProc.ssid = ssid; connectProc.running = true }
                    }
                }
            }

            // ----- halaman notifikasi: header (DnD, Clear) + daftar semua notifikasi -----
            Item {
                id: notifPage
                anchors.fill: parent
                anchors.margins: 14
                visible: win.page === "notif"

                // tombol di kanan atas
                Row {
                    id: notifBtns
                    anchors.right: parent.right
                    spacing: 6

                    // DnD toggle (terisi warna aksen saat aktif)
                    Rectangle {
                        width: dndText.implicitWidth + 16; height: 24; radius: 8
                        color: root.dnd ? root.cAccent : (dndArea.containsMouse ? root.cHover : root.cItem)
                        BarText {
                            id: dndText
                            anchors.centerIn: parent
                            font.pixelSize: 12
                            color: root.dnd ? root.cBg : root.cText
                            text: (root.dnd ? root.icBellOff : root.icBell) + " DnD"
                        }
                        MouseArea { id: dndArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.toggleDnd() }
                    }

                    // suara notifikasi on/off (terisi warna aksen saat aktif)
                    Rectangle {
                        width: soundText.implicitWidth + 16; height: 24; radius: 8
                        color: root.soundOn ? root.cAccent : (soundArea.containsMouse ? root.cHover : root.cItem)
                        BarText {
                            id: soundText
                            anchors.centerIn: parent
                            font.pixelSize: 12
                            color: root.soundOn ? root.cBg : root.cText
                            text: "Sound"
                        }
                        MouseArea { id: soundArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.toggleSound() }
                    }

                    // hapus semua
                    Rectangle {
                        width: clearText.implicitWidth + 16; height: 24; radius: 8
                        color: clearArea.containsMouse ? root.cHover : root.cItem
                        BarText { id: clearText; anchors.centerIn: parent; font.pixelSize: 12; text: "Clear" }
                        MouseArea { id: clearArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.clearAll() }
                    }
                }

                BarText {
                    anchors.verticalCenter: notifBtns.verticalCenter
                    font.pixelSize: 14
                    text: "Notifications" + (root.notifCount > 0 ? "  " + root.notifCount : "")
                }

                // daftar: terbaru di atas, klik kartu = hapus
                ListView {
                    anchors.top: notifBtns.bottom
                    anchors.topMargin: 12
                    anchors.bottom: parent.bottom
                    width: parent.width
                    spacing: 6
                    clip: true
                    model: ScriptModel { values: notifs.trackedNotifications.values.slice().reverse() }
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: nCol.implicitHeight + 16
                        radius: 8
                        color: root.cItem

                        // garis penanda notifikasi critical
                        Rectangle {
                            width: 3; height: parent.height - 12; radius: 2
                            anchors.left: parent.left; anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.cUrgent
                            visible: modelData.urgency === NotificationUrgency.Critical
                        }
                        Column {
                            id: nCol
                            anchors.fill: parent
                            anchors.margins: 8
                            anchors.leftMargin: 12
                            spacing: 2
                            BarText { text: modelData.appName; font.pixelSize: 10; opacity: 0.6; width: parent.width; elide: Text.ElideRight }
                            BarText { text: modelData.summary; width: parent.width; elide: Text.ElideRight }
                            BarText {
                                text: modelData.body
                                visible: text !== ""
                                width: parent.width
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                opacity: 0.6
                                font.weight: Font.Normal
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: modelData.dismiss() }
                    }
                }

                // tampilan kosong
                BarText { anchors.centerIn: parent; opacity: 0.5; text: "No notifications"; visible: root.notifCount === 0 }
            }

            // ----- halaman jam: jam besar + kalender + timer -----
            Item {
                id: clockPage
                anchors.fill: parent
                anchors.margins: 14
                visible: win.page === "clock"

                Column {
                    anchors.fill: parent
                    spacing: 8

                    // jam besar + tanggal lengkap
                    Column {
                        width: parent.width
                        BarText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 30
                            text: Qt.formatDateTime(clockSec.date, "HH:mm:ss")
                        }
                        BarText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 12
                            opacity: 0.6
                            text: Qt.formatDateTime(clockSec.date, "dddd, d MMMM yyyy")
                        }
                    }

                    // header kalender: < Bulan Tahun >   (klik judul = kembali ke hari ini)
                    Item {
                        width: parent.width
                        height: 26
                        Rectangle {
                            width: 26; height: 26; radius: 8
                            anchors.left: parent.left
                            color: prevArea.containsMouse ? root.cHover : root.cItem
                            BarText { anchors.centerIn: parent; text: "‹" }
                            MouseArea { id: prevArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.calShift(-1) }
                        }
                        BarText {
                            anchors.centerIn: parent
                            text: Qt.formatDate(new Date(root.calYear, root.calMonth, 1), "MMMM yyyy")
                            MouseArea { anchors.fill: parent; onClicked: root.calToday() }
                        }
                        Rectangle {
                            width: 26; height: 26; radius: 8
                            anchors.right: parent.right
                            color: nextArea.containsMouse ? root.cHover : root.cItem
                            BarText { anchors.centerIn: parent; text: "›" }
                            MouseArea { id: nextArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.calShift(1) }
                        }
                    }

                    // nama hari
                    Row {
                        height: 18
                        Repeater {
                            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                            delegate: BarText {
                                required property string modelData
                                width: clockPage.width / 7
                                height: 18
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: 11
                                opacity: 0.55
                                text: modelData
                            }
                        }
                    }

                    // tanggal (hari ini = terisi warna aksen)
                    Grid {
                        columns: 7
                        Repeater {
                            model: root.calCells
                            delegate: Rectangle {
                                id: dayCell
                                required property var modelData
                                width: clockPage.width / 7
                                height: 28
                                radius: 8
                                color: modelData.today ? root.cAccent : (dayArea.containsMouse ? root.cHover : "transparent")
                                border.width: modelData.key === root.selDate ? 1 : 0
                                border.color: modelData.today ? root.cBg : root.cAccent
                                BarText {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: -2
                                    font.pixelSize: 12
                                    text: dayCell.modelData.day
                                    color: dayCell.modelData.today ? root.cBg : root.cText
                                    opacity: !dayCell.modelData.inMonth ? 0.3
                                           : (dayCell.modelData.weekend && !dayCell.modelData.today ? 0.75 : 1)
                                }
                                // titik kecil = ada jadwal di hari itu
                                Rectangle {
                                    visible: dayCell.modelData.has
                                    width: 4; height: 4; radius: 2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 3
                                    color: dayCell.modelData.today ? root.cBg : root.cAccent
                                }
                                MouseArea {
                                    id: dayArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        root.selDate = dayCell.modelData.key
                                        if (!dayCell.modelData.inMonth) {        // klik tanggal bulan lain: pindah ke bulan itu
                                            root.calYear = dayCell.modelData.year
                                            root.calMonth = dayCell.modelData.month
                                        }
                                        root.clockTab = "schedule"
                                    }
                                }
                            }
                        }
                    }

                    // tab bawah: Schedule | Timer
                    Row {
                        spacing: 6
                        Repeater {
                            model: [ { k: "schedule", t: "Schedule" }, { k: "timer", t: "Timer" } ]
                            delegate: Rectangle {
                                required property var modelData
                                width: (clockPage.width - 6) / 2
                                height: 24
                                radius: 8
                                color: root.clockTab === modelData.k ? root.cAccent : (tabArea2.containsMouse ? root.cHover : root.cItem)
                                BarText {
                                    anchors.centerIn: parent
                                    font.pixelSize: 12
                                    color: root.clockTab === parent.modelData.k ? root.cBg : root.cText
                                    text: parent.modelData.t
                                }
                                MouseArea { id: tabArea2; anchors.fill: parent; hoverEnabled: true; onClicked: root.clockTab = parent.modelData.k }
                            }
                        }
                    }

                    Item {
                        id: tabArea
                        width: parent.width
                        height: 140

                        // ----- tab jadwal -----
                        Item {
                            id: schedTab
                            anchors.fill: parent
                            visible: root.clockTab === "schedule"

                            BarText {
                                id: schedTitle
                                font.pixelSize: 12
                                opacity: 0.7
                                text: "Schedule  -  " + root.fmtKey(root.selDate)
                            }
                            ListView {
                                id: schedList
                                anchors.top: schedTitle.bottom
                                anchors.topMargin: 6
                                width: parent.width
                                height: 80
                                spacing: 4
                                clip: true
                                model: root.itemsFor(root.selDate)
                                delegate: Rectangle {
                                    id: schedRow
                                    required property int index
                                    required property string modelData
                                    width: ListView.view.width
                                    height: 24
                                    radius: 8
                                    color: root.cItem
                                    BarText {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.right: delBtn.left
                                        anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                        text: schedRow.modelData
                                    }
                                    BarText {
                                        id: delBtn
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "×"
                                        opacity: delArea.containsMouse ? 1 : 0.5
                                        MouseArea {
                                            id: delArea
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            hoverEnabled: true
                                            onClicked: root.schedRemove(root.selDate, schedRow.index)
                                        }
                                    }
                                }
                            }
                            BarText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 52
                                visible: root.itemsFor(root.selDate).length === 0
                                opacity: 0.5
                                font.pixelSize: 12
                                text: "No schedule on this day"
                            }
                            // kotak ketik jadwal baru (klik lalu ketik, Enter = tambah)
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 30
                                radius: 8
                                color: root.cItem
                                border.width: schedInput.activeFocus ? 1 : 0
                                border.color: root.cAccent
                                TextInput {
                                    id: schedInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: root.cText
                                    font.family: "Iosevka"
                                    font.pixelSize: 13
                                    font.weight: Font.ExtraBold
                                    clip: true
                                    selectByMouse: true
                                    maximumLength: 120
                                    onAccepted: { root.schedAdd(root.selDate, text); text = "" }
                                    Keys.onEscapePressed: text = ""
                                }
                                BarText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    visible: schedInput.text === ""
                                    opacity: 0.4
                                    font.pixelSize: 12
                                    text: "type a schedule, press Enter to add"
                                }
                            }
                        }

                        // ----- tab timer -----
                        Column {
                            id: timerTab
                            width: parent.width
                            spacing: 8
                            visible: root.clockTab === "timer"

                    // sisa waktu timer: klik = ketik durasi sendiri, scroll = +/- 1 menit
                    Item {
                        id: timerBox
                        width: parent.width
                        height: 34
                        property bool editing: false

                        BarText {
                            anchors.centerIn: parent
                            visible: !timerBox.editing
                            font.pixelSize: 26
                            color: root.timerRunning ? root.cAccent : root.cText
                            text: root.fmtTime(root.timerLeft)
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { timerBox.editing = true; timerInput.text = ""; timerInput.forceActiveFocus() }
                                onWheel: wheel => root.timerAdd(wheel.angleDelta.y > 0 ? 60 : -60)
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            visible: timerBox.editing
                            width: 170; height: 32; radius: 8
                            color: root.cItem
                            border.width: 1
                            border.color: root.cAccent

                            TextInput {
                                id: timerInput
                                anchors.fill: parent
                                anchors.margins: 4
                                horizontalAlignment: TextInput.AlignHCenter
                                verticalAlignment: TextInput.AlignVCenter
                                color: root.cText
                                font.family: "Iosevka"
                                font.pixelSize: 20
                                font.weight: Font.ExtraBold
                                inputMethodHints: Qt.ImhPreferNumbers
                                validator: RegularExpressionValidator { regularExpression: /^[0-9:]{0,8}$/ }
                                Keys.onEscapePressed: timerBox.editing = false
                                onAccepted: {                       // Enter = pasang durasi lalu langsung start
                                    const sec = root.parseDuration(text)
                                    timerBox.editing = false
                                    if (sec > 0) { root.timerSet(sec); root.timerToggle() }
                                }
                                onActiveFocusChanged: if (!activeFocus) timerBox.editing = false
                            }
                            BarText {                               // petunjuk saat kosong
                                anchors.centerIn: parent
                                visible: timerInput.text === ""
                                opacity: 0.4
                                font.pixelSize: 12
                                text: "min  atau  mm:ss"
                            }
                        }
                    }

                    // progress timer
                    Rectangle {
                        width: parent.width; height: 4; radius: 2
                        color: root.cItem
                        Rectangle {
                            height: parent.height; radius: 2
                            color: root.cAccent
                            width: root.timerTotal > 0 ? parent.width * Math.min(1, root.timerLeft / root.timerTotal) : 0
                        }
                    }

                    // pilihan cepat + tambah/kurang waktu
                    Row {
                        spacing: 6
                        Repeater {
                            model: [
                                { t: "1m",  s: 60,   add: false },
                                { t: "5m",  s: 300,  add: false },
                                { t: "10m", s: 600,  add: false },
                                { t: "25m", s: 1500, add: false },
                                { t: "+1m", s: 60,   add: true  },
                                { t: "-1m", s: -60,  add: true  }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: (clockPage.width - 5 * 6) / 6
                                height: 24
                                radius: 8
                                color: qArea.containsMouse ? root.cHover : root.cItem
                                BarText { anchors.centerIn: parent; font.pixelSize: 12; text: parent.modelData.t }
                                MouseArea {
                                    id: qArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (parent.modelData.add) root.timerAdd(parent.modelData.s)
                                        else root.timerSet(parent.modelData.s)
                                    }
                                }
                            }
                        }
                    }

                    // start/pause + reset
                    Row {
                        spacing: 8
                        Rectangle {
                            width: (clockPage.width - 8) / 2
                            height: 28
                            radius: 8
                            color: root.timerRunning ? root.cAccent : (startArea.containsMouse ? root.cHover : root.cItem)
                            BarText {
                                anchors.centerIn: parent
                                font.pixelSize: 12
                                color: root.timerRunning ? root.cBg : root.cText
                                text: root.timerRunning ? "Pause" : "Start"
                            }
                            MouseArea { id: startArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.timerToggle() }
                        }
                        Rectangle {
                            width: (clockPage.width - 8) / 2
                            height: 28
                            radius: 8
                            color: resetArea.containsMouse ? root.cHover : root.cItem
                            BarText { anchors.centerIn: parent; font.pixelSize: 12; text: "Reset" }
                            MouseArea { id: resetArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.timerReset() }
                        }
                    }
                        }   // timerTab
                    }       // tabArea
                }
            }

            // ----- halaman audio: volume + preset + equalizer 10 band -----
            Item {
                id: audioPage
                anchors.fill: parent
                anchors.margins: 14
                visible: win.page === "audio"

                // baris volume: klik teks = mute / unmute
                BarText {
                    id: volTitle
                    font.pixelSize: 14
                    text: root.muted ? "󰝟  Muted"
                          : root.volIcons[Math.min(2, Math.floor(root.vol * 3))] + "  " + Math.round(root.vol * 100) + "%"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted }
                    }
                }
                MiniSlider {
                    id: volSlider
                    anchors.top: volTitle.bottom
                    anchors.topMargin: 8
                    width: parent.width
                    height: 22
                    value: root.vol
                    opacity: root.muted ? 0.4 : 1
                    onMoved: v => root.setVolume(v)
                }

                // tombol preset
                Row {
                    id: presetRow
                    anchors.top: volSlider.bottom
                    anchors.topMargin: 16
                    spacing: 8
                    Repeater {
                        model: ["Flat", "Bass", "Vocal", "Treble"]
                        delegate: Rectangle {
                            required property string modelData
                            width: (audioPage.width - 24) / 4
                            height: 28
                            radius: 8
                            color: pArea.containsMouse ? root.cHover : root.cItem
                            BarText { anchors.centerIn: parent; text: parent.modelData; font.pixelSize: 12 }
                            MouseArea {
                                id: pArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.loadPreset(parent.modelData)
                            }
                        }
                    }
                }

                // 10 slider vertikal (31Hz ... 16kHz), gain -12..+12 dB, isian mulai dari tengah (0 dB)
                Row {
                    anchors.top: presetRow.bottom
                    anchors.topMargin: 14
                    anchors.bottom: parent.bottom
                    width: parent.width
                    Repeater {
                        model: 10
                        delegate: Item {
                            id: band
                            required property int index
                            width: audioPage.width / 10
                            height: parent.height

                            BarText {                                  // angka gain di atas
                                id: gainText
                                anchors.horizontalCenter: parent.horizontalCenter
                                font.pixelSize: 10
                                opacity: 0.7
                                text: root.fmtGain(root.eqGains[band.index])
                            }
                            MiniSlider {
                                anchors.top: gainText.bottom
                                anchors.topMargin: 4
                                anchors.bottom: freqText.top
                                anchors.bottomMargin: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 20
                                vertical: true
                                from: -12
                                to: 12
                                origin: 0.5
                                value: root.eqGains[band.index]
                                onMoved: v => root.setBand(band.index, v)
                            }
                            BarText {                                  // label frekuensi di bawah
                                id: freqText
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                font.pixelSize: 10
                                opacity: 0.7
                                text: root.eqFreqs[band.index]
                            }
                        }
                    }
                }
            }
        }
        Corner { fill: root.cBg; anchors.right: panel.left; anchors.top: bar.bottom; visible: panel.height > 4 && !root.island }

        // ================= TOAST (notifikasi baru: kartu melayang di kiri atas) =================
        Rectangle {
            id: toast
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.top: parent.top
            anchors.topMargin: root.island ? 12 : root.barHeight + 10
            width: 340
            height: root.toastOpen ? 60 : 0
            color: root.cBg
            radius: 12
            border.width: root.toastOpen ? 1 : 0
            border.color: root.cItem
            clip: true
            opacity: root.toastOpen ? 1 : 0
            Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 2
                BarText { text: root.toastSummary; width: parent.width; elide: Text.ElideRight }
                BarText { text: root.toastBody; width: parent.width; elide: Text.ElideRight; opacity: 0.6; font.weight: Font.Normal }
            }
            // klik kartu = tutup
            MouseArea { anchors.fill: parent; onClicked: { root.toastOpen = false; toastTimer.stop() } }
        }
    }
    // ================= PENANGKAP KLIK: selama rofi terbuka, klik di mana saja = tutup rofi =================
    // Jendela transparan layar penuh (di bawah bar). Rofi tampil di layer overlay jadi tetap di atasnya.
    PanelWindow {
        id: catcher
        visible: rofiProc.running
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.namespace: "dynamic-catcher"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: Quickshell.execDetached(["pkill", "-x", "rofi"])
        }
    }
}
