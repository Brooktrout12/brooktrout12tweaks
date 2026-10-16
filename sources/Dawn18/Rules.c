#include "Rules.h"
#include <string.h>

static bool starts(const char *s, const char *prefix) {
    return s && strncmp(s, prefix, strlen(prefix)) == 0;
}
static bool ends(const char *s, const char *suffix) {
    if (!s) return false;
    size_t n = strlen(s), m = strlen(suffix);
    return n >= m && memcmp(s + n - m, suffix, m) == 0;
}

// This is called from the initializer BEFORE Foundation, NSBundle, preferences,
// dispatch blocks or hooks. Framework presence alone is not an app identity.
D18Process D18ProcessForPath(const char *path) {
    if (!path || !*path || strstr(path, "/../") || strstr(path, "/./")) return D18ProcessExcluded;
    if (!strcmp(path, "/System/Library/CoreServices/SpringBoard.app/SpringBoard") ||
        !strcmp(path, "/Applications/SpringBoard.app/SpringBoard")) return D18ProcessSpringBoard;
    if (!(starts(path, "/Applications/") || starts(path, "/var/jb/Applications/") ||
          starts(path, "/var/containers/Bundle/Application/") ||
          starts(path, "/private/var/containers/Bundle/Application/"))) return D18ProcessExcluded;
    if (strstr(path, ".appex/") || strstr(path, ".xpc/") || strstr(path, "/PlugIns/") ||
        strstr(path, "/Frameworks/") || strstr(path, "/XPCServices/")) return D18ProcessExcluded;
    const char *slash = strrchr(path, '/');
    if (!slash || !slash[1] || slash - path < 4 || memcmp(slash - 4, ".app", 4)) return D18ProcessExcluded;
    const char *executable = slash + 1;
    const char *excluded[] = {
        "SpringBoard", "backboardd", "fileproviderd", "filecoordinationd", "sharingd",
        "bird", "cloudd", "nsurlsessiond", "chronod", "WidgetRenderer",
        "PreBoard", "InCallService", "RemoteUI", "WebContent", "AuthenticationServicesUI"
    };
    for (size_t i = 0; i < sizeof(excluded) / sizeof(excluded[0]); i++)
        if (!strcmp(executable, excluded[i])) return D18ProcessExcluded;
    return D18ProcessApplication;
}

// Runtime name matching is intentionally restricted to UI classes. In
// particular, SBFolderView/SBFolderController also cover the entire Home Screen
// and MUST NOT be used as folder override roots.
D18Element D18ElementForClassName(const char *name) {
    if (!name) return D18None;
    while (*name == '_') name++;
    const struct { const char *name; D18Element element; } names[] = {
        {"SBFolderBackgroundView", D18Folders},
        {"SBFolderIconBackgroundView", D18Folders},
        {"SBFolderIconBlurryBackgroundView", D18Folders},
        // A context marker only: style the tile's background, not its mini icons.
        {"SBFolderIconImageView", D18FolderIconSurface},
        {"SBFloatyFolderView", D18Folders},
        {"SBHIconViewContextMenuWrapperViewController", D18QuickActions},
        // Material marker only; ownership still comes from the icon interaction.
        {"UIContextMenuListView", D18ContextMenuListSurface},
        {"SBDockView", D18Dock},
        {"SBDockBackgroundView", D18Dock},
        {"SBFloatingDockPlatterView", D18Dock},
        {"NCNotificationShortLookView", D18NotificationSurface},
        {"NCNotificationLongLookView", D18NotificationSurface},
        {"NCNotificationShortLookViewController", D18NotificationSurface},
        {"NCNotificationLongLookViewController", D18NotificationSurface},
        // Expanded notification UI is reparented; its controller's delegate
        // identifies whether it came from a banner or Notification Center.
        {"NCExpandedPlatterView", D18NotificationSurface},
        {"NCExpandedPlatterViewController", D18NotificationSurface},
        {"NCNotificationListClearButton", D18Buttons},
        {"NCNotificationListSectionHeaderClearButton", D18Buttons},
        {"NCNotificationListSectionHeaderView", D18Buttons},
        {"NCNotificationListCoalescingControlsView", D18Buttons},
        // Per-notification swipe actions belong to Notifications, not the
        // separate list-wide X / Clear All controls.
        {"NCNotificationListCellActionButton", D18Notifications},
        {"NCNotificationListCellActionButtonsView", D18Notifications},
        {"NCNotificationListSectionRevealHintView", D18Buttons},
        // iOS 18 PLSwipeInteraction creates these shared PlatterKit controls.
        // They become Notifications only beneath a notification source view.
        {"PLActionButtonsPresentingView", D18PlatterActionSurface},
        {"PLPlatterActionButtonsView", D18PlatterActionSurface},
        {"PLPlatterActionButton", D18PlatterActionSurface},
        {"SBRingerHUDViewController", D18RingerVolume},
        {"SBRingerPillView", D18RingerVolume},
        {"SBElasticVolumeViewController", D18RingerVolume}
    };
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++)
        if (!strcmp(name, names[i].name)) return names[i].element;
    bool uiClass = ends(name, "View") || ends(name, "ViewController") || ends(name, "Controller");
    if (uiClass && starts(name, "SBHLibrary")) return D18AppLibrary;
    if (uiClass && (starts(name, "SBHWidget") || starts(name, "CHUISWidget") ||
                    starts(name, "WGWidgetPlatter"))) return D18Widgets;
    if (uiClass && starts(name, "NCNotificationBanner")) return D18Banners;
    return D18None;
}

bool D18IsBannerContext(const char *name) {
    if (!name) return false;
    while (*name == '_') name++;
    return starts(name, "NCNotificationBanner") || starts(name, "SBNotificationBanner") ||
           starts(name, "SBBanner") || starts(name, "SBFNotificationBanner");
}

bool D18IsNotificationOptionsSourceClass(const char *name) {
    if (!name) return false;
    while (*name == '_') name++;
    return !strcmp(name, "NCNotificationListCellActionButton") ||
           !strcmp(name, "NCNotificationListCellActionButtonsView") ||
           !strcmp(name, "NCNotificationListCell");
}

int D18ValidatedStyle(long value) { return value == 1 || value == 2 ? (int)value : 0; }

int D18ValidatedPreference(D18Element element, double value) {
    if (element < 0 || element >= D18ElementCount) return 0;
    if (value == 1.0 || value == 2.0) return (int)value;
    return element == D18QuickActions && value == D18IOS10Style ? D18IOS10Style : 0;
}

int D18SelectionForElement(D18Element element, int preference) {
    // The classic material uses native light text/icon styling (dark ink).
    // Its separate blur treatment is applied only to an icon-owned menu list.
    if (element == D18QuickActions && preference == D18IOS10Style) return 1;
    int style = D18ValidatedStyle(preference);
    // A reused card can retain an explicit style captured while forced or
    // created under another theme. Default must not restore that stale value.
    return element == D18Notifications && !style ? D18InheritAppearance : style;
}

long D18Transition(D18StyleState *state, long currentStyle, int selection) {
    int style = D18ValidatedStyle(selection);
    if (style || selection == D18InheritAppearance) {
        if (!state->managed) { state->nativeStyle = currentStyle; state->managed = true; }
        return style;
    }
    if (!state->managed) return currentStyle;
    state->managed = false;
    return state->nativeStyle;
}

// Called only for the system/app's setter calls. Our own applications bypass
// the hook, so the native value remains recoverable when Default is selected.
long D18InterceptNativeStyle(D18StyleState *state, long requestedStyle, int selection) {
    int style = D18ValidatedStyle(selection);
    state->managed = style != 0 || selection == D18InheritAppearance;
    state->nativeStyle = requestedStyle;
    return state->managed ? style : requestedStyle;
}
