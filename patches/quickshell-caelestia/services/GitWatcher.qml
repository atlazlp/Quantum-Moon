pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.utils

Singleton {
    id: root

    // -----------------------------------------------------------------------
    // Public state (read by UI)
    // -----------------------------------------------------------------------
    property var prs: []
    property var completedPrs: []
    property var commentItems: []
    property var mentionItems: []
    property int overdueCount: 0   // raw from daemon, unfiltered
    property int mentionCount: 0   // raw from daemon, unfiltered
    property bool loading: false
    property string lastError: ""
    property string lastUpdated: ""

    // Mute/dismiss state managed here (not by daemon)
    property var mutedIds: []      // [prId, ...]
    property var dismissedIds: []  // [prId, ...]

    // -----------------------------------------------------------------------
    // Translations — add new languages by appending an entry to each key.
    // Strings used in popout and config modal reference GitWatcher.t.keyName.
    // -----------------------------------------------------------------------
    readonly property string _lang: (_configData?.language ?? "en").toLowerCase()

    readonly property var t: _lang.startsWith("pt") ? _pt : _en

    readonly property var _en: ({
        // Header / tabs
        widgetTitle:      "Azure DevOps",
        tabFeed:          "Feed",
        tabArchived:      "Archived",
        // Feed states
        nothingToReview:  "Nothing to review",
        noArchived:       "No archived items",
        // PR chip labels
        chipStalled:      "stalled",
        chipMine:         "mine",
        chipPR:           "PR",
        chipMention:      "mention",
        chipComment:      "comment",
        // PR row
        stalledPrefix:    "stalled ",
        // Footer
        refresh:          "Refresh",
        config:           "Config",
        updatedAt:        "Updated %1",
        // Archive labels
        labelDismissed:   "dismissed",
        labelMerged:      "merged",
        // Card actions
        open:             "Open",
        mute:             "Mute",
        unmute:           "Unmute",
        dismiss:          "Dismiss",
        undismiss:        "Restore",
        // Config modal
        configTitle:      "GitWatcher Config",
        sectionCredentials: "Credentials",
        fieldPat:         "Personal Access Token",
        fieldPatHint:     "Required scopes: Code (Read), Graph (Read)",
        fieldOrgUrl:      "Organization URL",
        fieldOrgUrlHint:  "https://dev.azure.com/myorg",
        fieldIdentity:    "My identity (email / UPN)",
        fieldIdentityHint:"For mention and owned PR detection",
        sectionPolling:   "Polling",
        fieldInterval:    "Poll interval (seconds)",
        fieldIntervalHint:"Minimum 10",
        sectionNotifs:    "Notifications",
        notifNewPr:       "New PR",
        notifComment:     "Comment on my PR",
        notifMention:     "Mention (@me)",
        fieldOverdueMin:  "Overdue threshold (min)",
        fieldOverdueHint: "Stalled + unapproved after this long",
        sectionColors:    "Colors",
        fieldOverdueColor:"Overdue color",
        fieldMentionColor:"Mention color",
        sectionRepos:     "Repositories",
        reposEmptyHint:   "No repos loaded yet — save credentials first and wait for a poll.",
        sectionLanguage:  "Language",
        langEnglish:      "English",
        langPortuguese:   "Português (BR)",
        cancel:           "Cancel",
        apply:            "Apply",
    })

    readonly property var _pt: ({
        widgetTitle:      "Azure DevOps",
        tabFeed:          "Feed",
        tabArchived:      "Arquivados",
        nothingToReview:  "Nada para revisar",
        noArchived:       "Sem itens arquivados",
        chipStalled:      "parado",
        chipMine:         "meu",
        chipPR:           "PR",
        chipMention:      "menção",
        chipComment:      "comentário",
        stalledPrefix:    "parado ",
        refresh:          "Atualizar",
        config:           "Configurar",
        updatedAt:        "Atualizado %1",
        labelDismissed:   "arquivado",
        labelMerged:      "mesclado",
        open:             "Abrir",
        mute:             "Silenciar",
        unmute:           "Ativar",
        dismiss:          "Arquivar",
        undismiss:        "Restaurar",
        configTitle:      "Config GitWatcher",
        sectionCredentials: "Credenciais",
        fieldPat:         "Token de Acesso Pessoal",
        fieldPatHint:     "Escopos necessários: Code (Read), Graph (Read)",
        fieldOrgUrl:      "URL da Organização",
        fieldOrgUrlHint:  "https://dev.azure.com/minhaorg",
        fieldIdentity:    "Minha identidade (email / UPN)",
        fieldIdentityHint:"Para detecção de menções e PRs meus",
        sectionPolling:   "Intervalo de consulta",
        fieldInterval:    "Intervalo (segundos)",
        fieldIntervalHint:"Mínimo 10",
        sectionNotifs:    "Notificações",
        notifNewPr:       "Novo PR",
        notifComment:     "Comentário no meu PR",
        notifMention:     "Menção (@eu)",
        fieldOverdueMin:  "Limite de atraso (min)",
        fieldOverdueHint: "Parado + não aprovado após este tempo",
        sectionColors:    "Cores",
        fieldOverdueColor:"Cor de atraso",
        fieldMentionColor:"Cor de menção",
        sectionRepos:     "Repositórios",
        reposEmptyHint:   "Nenhum repositório carregado — salve as credenciais e aguarde.",
        sectionLanguage:  "Idioma",
        langEnglish:      "English",
        langPortuguese:   "Português (BR)",
        cancel:           "Cancelar",
        apply:            "Aplicar",
    })

    readonly property bool configured: {
        const d = _configData;
        return d !== null && typeof d === "object" &&
               typeof d.pat === "string" && d.pat.length > 0 &&
               typeof d.organizationUrl === "string" && d.organizationUrl.length > 0;
    }

    readonly property bool active: !GameMode.enabled &&
                                   (GlobalConfig.bar?.status?.showGitWatcher !== false)

    // -----------------------------------------------------------------------
    // Derived sets (fast lookup)
    // -----------------------------------------------------------------------
    readonly property var _mutedSet: {
        const s = {};
        for (const id of mutedIds) s[id] = true;
        return s;
    }
    readonly property var _dismissedSet: {
        const s = {};
        for (const id of dismissedIds) s[id] = true;
        return s;
    }

    // -----------------------------------------------------------------------
    // Computed feeds
    // -----------------------------------------------------------------------

    // Main feed: non-dismissed PRs + non-dismissed comments/mentions
    readonly property var mainFeedItems: {
        const items = [];
        for (const pr of prs) {
            if (_dismissedSet[pr.id]) continue;
            items.push({
                uid: `pr-${pr.id}`,
                prId: pr.id,
                itemType: "pr",
                title: pr.title,
                repo: pr.repo,
                project: pr.project ?? "",
                url: pr.url,
                sourceBranch: pr.sourceBranch ?? "",
                targetBranch: pr.targetBranch ?? "",
                ageMinutes: pr.ageMinutes ?? 0,
                stallMinutes: pr.stallMinutes ?? 0,
                isOverdue: pr.isOverdue ?? false,
                isOwned: pr.isOwned ?? false,
                isApproved: pr.isApproved ?? false,
                hasMentions: pr.hasMentions ?? false,
                hasUnreadComments: pr.hasUnreadComments ?? false,
                isMuted: !!_mutedSet[pr.id],
            });
        }
        for (const c of commentItems) {
            if (_dismissedSet[c.prId]) continue;
            items.push({
                uid: `comment-${c.prId}-${c.author}`,
                prId: c.prId,
                itemType: "comment",
                title: c.prTitle ?? "",
                repo: c.repo ?? "",
                project: c.project ?? "",
                url: c.url,
                author: c.author ?? "",
                excerpt: c.excerpt ?? "",
                isMuted: !!_mutedSet[c.prId],
            });
        }
        for (const m of mentionItems) {
            if (_dismissedSet[m.prId]) continue;
            items.push({
                uid: `mention-${m.prId}-${m.author}`,
                prId: m.prId,
                itemType: "mention",
                title: m.prTitle ?? "",
                repo: m.repo ?? "",
                project: m.project ?? "",
                url: m.url,
                author: m.author ?? "",
                excerpt: m.excerpt ?? "",
                isMuted: !!_mutedSet[m.prId],
            });
        }
        // Sort: overdue first, mentions/comments next, then rest by age
        items.sort((a, b) => {
            const score = x => (x.isOverdue ? 8 : 0) + (x.itemType === "mention" ? 4 : 0) +
                               (x.hasMentions ? 4 : 0) + (x.itemType === "comment" ? 2 : 0) +
                               (x.hasUnreadComments ? 2 : 0);
            const diff = score(b) - score(a);
            if (diff !== 0) return diff;
            return (b.stallMinutes ?? b.ageMinutes ?? 0) - (a.stallMinutes ?? a.ageMinutes ?? 0);
        });
        return items;
    }

    // Archive feed: dismissed open PRs at top, then completed PRs
    readonly property var archiveFeedItems: {
        const items = [];
        for (const pr of prs) {
            if (!_dismissedSet[pr.id]) continue;
            items.push({
                uid: `arch-${pr.id}`,
                prId: pr.id,
                itemType: "pr_archived",
                title: pr.title,
                repo: pr.repo,
                project: pr.project ?? "",
                url: pr.url,
                targetBranch: pr.targetBranch ?? "",
                ageMinutes: pr.ageMinutes ?? 0,
                isOwned: pr.isOwned ?? false,
            });
        }
        for (const pr of completedPrs) {
            items.push({
                uid: `comp-${pr.id}`,
                prId: pr.id,
                itemType: "pr_completed",
                title: pr.title,
                repo: pr.repo,
                project: pr.project ?? "",
                url: pr.url,
                targetBranch: pr.targetBranch ?? "",
                ageMinutes: pr.ageMinutes ?? 0,
                isOwned: pr.isOwned ?? false,
            });
        }
        return items;
    }

    // Attention count: non-muted, non-dismissed items needing action
    readonly property int attentionCount: {
        let n = 0;
        for (const pr of prs) {
            if (_dismissedSet[pr.id] || _mutedSet[pr.id]) continue;
            if (pr.isOverdue || pr.hasMentions || pr.hasUnreadComments) n++;
        }
        n += commentItems.filter(c => !_dismissedSet[c.prId] && !_mutedSet[c.prId]).length;
        n += mentionItems.filter(m => !_dismissedSet[m.prId] && !_mutedSet[m.prId]).length;
        return n;
    }

    // Overdue count excluding muted/dismissed (drives icon state)
    readonly property int filteredOverdueCount: {
        let n = 0;
        for (const pr of prs) {
            if (!_dismissedSet[pr.id] && !_mutedSet[pr.id] && (pr.isOverdue ?? false)) n++;
        }
        return n;
    }

    // -----------------------------------------------------------------------
    // Mute / Dismiss operations
    // -----------------------------------------------------------------------
    function mute(prId: int): void {
        if (!_mutedSet[prId])
            mutedIds = [...mutedIds, prId];
        _saveMuted();
    }

    function unmute(prId: int): void {
        mutedIds = mutedIds.filter(x => x !== prId);
        _saveMuted();
    }

    function dismiss(prId: int): void {
        if (!_dismissedSet[prId])
            dismissedIds = [...dismissedIds, prId];
        if (!_mutedSet[prId])   // also mute so daemon skips notifications
            mutedIds = [...mutedIds, prId];
        _saveMuted();
    }

    function undismiss(prId: int): void {
        dismissedIds = dismissedIds.filter(x => x !== prId);
        _saveMuted();
    }

    function _saveMuted(): void {
        const content = JSON.stringify({muted: mutedIds, dismissed: dismissedIds}, null, 2);
        saveMutedProc.command = [
            "python3", "-c",
            "import sys, os; open(sys.argv[1],'w').write(sys.argv[2])",
            root._mutedPath,
            content
        ];
        saveMutedProc.running = true;
    }

    // -----------------------------------------------------------------------
    // Private state
    // -----------------------------------------------------------------------
    property var _configData: null

    readonly property string _configPath: Quickshell.env("HOME") + "/.config/caelestia/git-watcher.json"
    readonly property string _statePath: Quickshell.env("HOME") + "/.local/state/caelestia/git-watcher-state.json"
    readonly property string _mutedPath: Quickshell.env("HOME") + "/.local/state/caelestia/git-watcher-muted.json"
    readonly property string _pidPath: Quickshell.env("HOME") + "/.local/state/caelestia/git-watcher.pid"
    readonly property string _daemonPath: Paths.config + "/../caelestia/scripts/git-watcher.py"

    // -----------------------------------------------------------------------
    // File watchers
    // -----------------------------------------------------------------------
    FileView {
        id: configFile
        path: root._configPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            try { root._configData = JSON.parse(text()); }
            catch (e) { console.warn("GitWatcher: config parse error:", e); root._configData = null; }
        }
        onFileChanged: reload()
        onLoadFailed: err => { root._configData = null; }
        Component.onCompleted: reload()
    }

    FileView {
        id: stateFile
        path: root._statePath
        watchChanges: true
        printErrors: false
        onLoaded: root._applyState(text())
        onFileChanged: reload()
    }

    FileView {
        id: mutedFile
        path: root._mutedPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.mutedIds = d.muted ?? [];
                root.dismissedIds = d.dismissed ?? [];
            } catch (e) {}
        }
        onFileChanged: reload()
    }

    function _applyState(text: string): void {
        try {
            const s = JSON.parse(text);
            root.prs = s.prs ?? [];
            root.completedPrs = s.completedPrs ?? [];
            root.commentItems = s.commentItems ?? [];
            root.mentionItems = s.mentionItems ?? [];
            root.overdueCount = s.overdueCount ?? 0;
            root.mentionCount = s.mentionCount ?? 0;
            root.lastError = s.error ?? "";
            root.lastUpdated = s.lastUpdated ?? "";
            root.loading = false;
        } catch (e) {
            root.lastError = "Failed to parse state";
        }
    }

    // -----------------------------------------------------------------------
    // Daemon process
    // -----------------------------------------------------------------------
    readonly property bool _daemonShouldRun: active && configured

    Process {
        id: daemon
        command: ["python3", root._daemonPath]
        running: root._daemonShouldRun
        onExited: exitCode => { if (root._daemonShouldRun) restartTimer.start(); }
    }

    Timer {
        id: restartTimer
        interval: 5000; repeat: false
        onTriggered: { if (root._daemonShouldRun && !daemon.running) daemon.running = true; }
    }

    // -----------------------------------------------------------------------
    // Manual refresh
    // -----------------------------------------------------------------------
    function refresh(): void {
        loading = true;
        sighupProc.running = true;
    }

    Process {
        id: sighupProc
        command: ["bash", "-c",
            "PID=$(cat " + root._pidPath + " 2>/dev/null) && [ -n \"$PID\" ] && kill -HUP \"$PID\""
        ]
        onExited: loadingFallback.restart()
    }

    Timer {
        id: loadingFallback; interval: 8000; repeat: false
        onTriggered: root.loading = false
    }

    // -----------------------------------------------------------------------
    // Apply config (from settings modal — always-alive singleton so close() is
    // called synchronously from the modal before any async work starts)
    // -----------------------------------------------------------------------
    function applyConfig(jsonText: string): void {
        applyWriteProc.pendingJson = jsonText;
        applyWriteProc.running = true;
    }

    Process {
        id: applyWriteProc
        property string pendingJson: ""
        command: [
            "python3", "-c",
            "import sys, os; open(sys.argv[1],'w').write(sys.argv[2]); os.chmod(sys.argv[1], 0o600)",
            root._configPath,
            applyWriteProc.pendingJson
        ]
        onExited: applySighupProc.running = true
    }

    Process {
        id: applySighupProc
        command: ["bash", "-c",
            "PID=$(cat " + root._pidPath + " 2>/dev/null) && [ -n \"$PID\" ] && kill -HUP \"$PID\""
        ]
    }

    // Async write for muted/dismissed file
    Process {
        id: saveMutedProc
    }
}
