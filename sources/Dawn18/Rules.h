#pragma once
#include <stdbool.h>
#include <stddef.h>

typedef enum {
    D18None = -1,
    D18Applications = 0, D18Folders, D18Notifications, D18Buttons,
    D18Widgets, D18Dock, D18Banners, D18AppLibrary, D18QuickActions,
    D18RingerVolume,
    D18ElementCount,
    D18NotificationSurface = 100,
    D18FolderIconSurface = 101,
    D18PlatterActionSurface = 102,
    D18ContextMenuListSurface = 103
} D18Element;

typedef enum { D18ProcessExcluded, D18ProcessApplication, D18ProcessSpringBoard } D18Process;
typedef struct { int values[D18ElementCount]; } D18Configuration;
typedef struct { bool managed; long nativeStyle; } D18StyleState;

// Internal effective selection, never written to the user's preferences.
// Keep an unspecified UIKit override so inherited appearance stays live.
enum { D18InheritAppearance = -1 };
// Stored only for Home Screen Quick Actions; never passed to UIKit as a style.
enum { D18IOS10Style = 3 };

D18Process D18ProcessForPath(const char *path);
D18Element D18ElementForClassName(const char *name);
bool D18IsBannerContext(const char *name);
bool D18IsNotificationOptionsSourceClass(const char *name);
int D18ValidatedStyle(long value);
int D18ValidatedPreference(D18Element element, double value);
int D18SelectionForElement(D18Element element, int preference);
long D18Transition(D18StyleState *state, long currentStyle, int selection);
long D18InterceptNativeStyle(D18StyleState *state, long requestedStyle, int selection);
