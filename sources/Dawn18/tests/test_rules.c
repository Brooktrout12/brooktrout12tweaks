#include "../Rules.h"
#include "../Preview.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>

int main(void) {
    // Adding a preference must not shift an existing stored choice/index.
    assert(D18Applications == 0 && D18Folders == 1 && D18Notifications == 2);
    assert(D18Buttons == 3 && D18Widgets == 4 && D18Dock == 5);
    assert(D18Banners == 6 && D18AppLibrary == 7 && D18QuickActions == 8);
    assert(D18RingerVolume == 9 && D18ElementCount == 10);
    D18Configuration fresh = {{0}};
    for (int i = 0; i < D18ElementCount; i++) assert(fresh.values[i] == 0);
    const char *excluded[] = {
        "/usr/libexec/fileproviderd", "/usr/libexec/filecoordinationd",
        "/usr/libexec/sharingd", "/usr/libexec/chronod",
        "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/com.apple.WebKit.WebContent",
        "/private/var/containers/Bundle/Application/ABC/Test.app/PlugIns/Provider.appex/Provider",
        "/var/containers/Bundle/Application/ABC/Test.app/Frameworks/Framework.framework/Binary",
        "/System/Library/CoreServices/RemoteUI.app/RemoteUI",
        "/Applications/Fake.app/fileproviderd", "/Applications/NotAnApplication/binary",
        "/Applications/Example.app/", "/Applications/Example.app/../fileproviderd",
        "/Applications/Example.app/./Example", NULL, ""
    };
    for (unsigned i = 0; i < sizeof(excluded) / sizeof(excluded[0]); i++)
        assert(D18ProcessForPath(excluded[i]) == D18ProcessExcluded);
    assert(D18ProcessForPath("/System/Library/CoreServices/SpringBoard.app/SpringBoard") == D18ProcessSpringBoard);
    assert(D18ProcessForPath("/Applications/Preferences.app/Preferences") == D18ProcessApplication);
    assert(D18ProcessForPath("/private/var/containers/Bundle/Application/ABC/ChatGPT.app/ChatGPT") == D18ProcessApplication);
    assert(D18ProcessForPath("/var/containers/Bundle/Application/ABC/MobileSafari.app/MobileSafari") == D18ProcessApplication);
    assert(D18ProcessForPath("/var/jb/Applications/ShareScope.app/ShareScope") == D18ProcessApplication);

    assert(D18ElementForClassName("SBRootFolderView") == D18None);
    assert(D18ElementForClassName("SBFolderView") == D18None);
    assert(D18ElementForClassName("SBFolderController") == D18None);
    assert(D18ElementForClassName("SBFolderIconBackgroundView") == D18Folders);
    assert(D18ElementForClassName("SBFolderIconImageView") == D18FolderIconSurface);
    assert(D18ElementForClassName("SBIconImageView") == D18None);
    assert(D18ElementForClassName("SBHIconViewContextMenuWrapperViewController") == D18QuickActions);
    assert(D18ElementForClassName("UIInterfaceActionGroupView") == D18None);
    assert(D18ElementForClassName("_UIContextMenuActionsListView") == D18None);
    assert(D18ElementForClassName("_UIContextMenuListView") == D18ContextMenuListSurface);
    assert(D18ElementForClassName("UIVisualEffectView") == D18None);
    assert(D18ElementForClassName("UIContextMenuListViewModel") == D18None);
    assert(D18ElementForClassName("SBDockView") == D18Dock);
    assert(D18ElementForClassName("NCNotificationShortLookView") == D18NotificationSurface);
    assert(D18ElementForClassName("NCNotificationLongLookViewController") == D18NotificationSurface);
    assert(D18ElementForClassName("NCExpandedPlatterViewController") == D18NotificationSurface);
    assert(D18ElementForClassName("NCExpandedPlatterView") == D18NotificationSurface);
    assert(D18ElementForClassName("PLExpandedPlatterView") == D18None);
    assert(D18ElementForClassName("NCNotificationListSectionHeaderView") == D18Buttons);
    assert(D18ElementForClassName("NCNotificationListClearButton") == D18Buttons);
    assert(D18ElementForClassName("NCNotificationListCellActionButton") == D18Notifications);
    assert(D18ElementForClassName("NCNotificationListCellActionButtonsView") == D18Notifications);
    // Shared PlatterKit classes are contextual markers, never unconditional
    // notification overrides. Runtime resolution also requires an NC ancestor.
    assert(D18ElementForClassName("PLPlatterActionButton") == D18PlatterActionSurface);
    assert(D18ElementForClassName("PLPlatterActionButtonsView") == D18PlatterActionSurface);
    assert(D18ElementForClassName("_PLActionButtonsPresentingView") == D18PlatterActionSurface);
    assert(D18ElementForClassName("PLSwipeInteraction") == D18None);
    assert(D18ElementForClassName("PLPlatterActionButtonModel") == D18None);
    assert(D18ElementForClassName("MTMaterialView") == D18None);
    assert(D18ElementForClassName("UIButton") == D18None);
    assert(D18ElementForClassName("SBRingerPillView") == D18RingerVolume);
    assert(D18ElementForClassName("SBRingerHUDViewController") == D18RingerVolume);
    assert(D18ElementForClassName("SBElasticVolumeViewController") == D18RingerVolume);
    assert(D18ElementForClassName("SBRingerControl") == D18None);
    assert(D18ElementForClassName("SBVolumeControl") == D18None);
    assert(D18ElementForClassName("SBElasticValueViewController") == D18None);
    assert(D18ElementForClassName("SBElasticBrightnessViewController") == D18None);
    assert(D18ElementForClassName("SBElasticSliderView") == D18None);
    assert(D18ElementForClassName("CCUIBaseSliderView") == D18None);
    // A whole cell is only an Options-menu source, not an appearance root.
    assert(D18ElementForClassName("NCNotificationListCell") == D18None);
    assert(D18IsNotificationOptionsSourceClass("NCNotificationListCellActionButton"));
    assert(D18IsNotificationOptionsSourceClass("NCNotificationListCellActionButtonsView"));
    assert(D18IsNotificationOptionsSourceClass("_NCNotificationListCell"));
    assert(!D18IsNotificationOptionsSourceClass("UIButton"));
    assert(!D18IsNotificationOptionsSourceClass("SBIconView"));
    assert(!D18IsNotificationOptionsSourceClass("_UIContextMenuView"));
    assert(!D18IsNotificationOptionsSourceClass("NCExpandedPlatterView"));
    assert(!D18IsNotificationOptionsSourceClass("PLPlatterActionButton"));
    assert(!D18IsNotificationOptionsSourceClass("PLActionButtonsPresentingView"));
    assert(!D18IsNotificationOptionsSourceClass("SBRingerPillView"));
    assert(!D18IsNotificationOptionsSourceClass("NCNotificationListCellActionButtonModel"));
    assert(!D18IsNotificationOptionsSourceClass(NULL));
    assert(D18ElementForClassName("CHUISWidgetHostViewController") == D18Widgets);
    assert(D18ElementForClassName("SBHLibraryPodBackgroundView") == D18AppLibrary);
    assert(D18ElementForClassName("_SBHLibraryView") == D18AppLibrary);
    assert(D18ElementForClassName("SBHLibraryModel") == D18None);
    assert(D18ElementForClassName("SBHWidgetConfiguration") == D18None);
    assert(D18ElementForClassName("UIWindow") == D18None);
    assert(D18IsBannerContext("NCNotificationBannerDestination"));
    assert(D18IsBannerContext("_SBBannerWindow"));
    assert(!D18IsBannerContext("NCNotificationListView"));
    assert(!D18IsBannerContext("NCExpandedPlatterViewController"));
    assert(D18IsBannerContext("SBNotificationBannerDestination"));

    D18StyleState state = {false, 0};
    assert(D18Transition(&state, 1, 0) == 1 && !state.managed);
    assert(D18Transition(&state, 1, 2) == 2 && state.managed && state.nativeStyle == 1);
    assert(D18Transition(&state, 2, 1) == 1 && state.nativeStyle == 1);
    assert(D18Transition(&state, 1, 0) == 1 && !state.managed);
    assert(D18Transition(&state, 0, 2) == 2 && state.nativeStyle == 0);
    assert(D18InterceptNativeStyle(&state, 1, 2) == 2 && state.nativeStyle == 1);
    assert(D18Transition(&state, 2, 0) == 1 && !state.managed);
    assert(D18InterceptNativeStyle(&state, 0, 2) == 2 && state.nativeStyle == 0);
    assert(D18Transition(&state, 2, -10) == 0 && !state.managed);
    assert(D18ValidatedStyle(100) == 0);
    assert(D18ValidatedStyle(-1) == 0);
    // The fourth persisted choice is valid only for Quick Actions. Reject
    // fractional/corrupt data rather than converting it to an appearance.
    for (int element = 0; element < D18ElementCount; element++) {
        D18Element kind = (D18Element)element;
        for (int value = 0; value <= 2; value++)
            assert(D18ValidatedPreference(kind, value) == value);
        assert(D18ValidatedPreference(kind, 3) == (kind == D18QuickActions ? 3 : 0));
        const double invalid[] = {-1, 1.5, 2.5, 3.5, 4, 100, NAN, INFINITY, -INFINITY};
        for (unsigned i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++)
            assert(D18ValidatedPreference(kind, invalid[i]) == 0);
    }
    assert(D18ValidatedPreference(D18None, 1) == 0);
    assert(D18ValidatedPreference(D18ContextMenuListSurface, 3) == 0);
    assert(D18ValidatedStyle(D18IOS10Style) == 0); // never a UIKit style enum
    assert(D18SelectionForElement(D18QuickActions, D18IOS10Style) == 1);
    assert(D18SelectionForElement(D18Notifications, D18IOS10Style) == D18InheritAppearance);
    for (long native = 0; native <= 2; native++) {
        D18StyleState menu = {false, 0};
        assert(D18Transition(&menu, native, D18SelectionForElement(D18QuickActions, 3)) == 1);
        assert(D18Transition(&menu, 1, D18SelectionForElement(D18QuickActions, 2)) == 2);
        assert(D18Transition(&menu, 2, D18SelectionForElement(D18QuickActions, 0)) == native);
        assert(!menu.managed);
    }
    assert(D18SelectionForElement(D18Notifications, 0) == D18InheritAppearance);
    assert(D18SelectionForElement(D18Notifications, 1) == 1);
    assert(D18SelectionForElement(D18Notifications, 2) == 2);
    assert(D18SelectionForElement(D18Notifications, 37) == D18InheritAppearance);
    for (int element = 0; element < D18ElementCount; element++) {
        if (element != D18Notifications)
            assert(D18SelectionForElement((D18Element)element, 0) == 0);
    }
    // HUD Default restores its native override; notifications keep their own
    // inherited-Default policy. No change to real volume or mute state exists.
    for (long native = 0; native <= 2; native++) {
        D18StyleState hud = {false, 0};
        assert(D18Transition(&hud, native, D18SelectionForElement(D18RingerVolume, 1)) == 1);
        assert(D18Transition(&hud, 1, D18SelectionForElement(D18RingerVolume, 2)) == 2);
        assert(D18Transition(&hud, 2, D18SelectionForElement(D18RingerVolume, 0)) == native);
        assert(!hud.managed);
    }
    // Default must clear a stale card override even if this instance was never
    // managed. A subsequent native setter must not pin it to an old light/dark
    // value either. Zero allows UIKit to inherit later parent theme changes.
    for (long captured = 0; captured <= 2; captured++) {
        for (long requested = 0; requested <= 2; requested++) {
            D18StyleState card = {false, 0};
            assert(D18Transition(&card, captured, D18InheritAppearance) == 0);
            assert(card.managed && card.nativeStyle == captured);
            assert(D18InterceptNativeStyle(&card, requested, D18InheritAppearance) == 0);
            assert(card.managed && card.nativeStyle == requested);
            assert(D18Transition(&card, 0, 1) == 1);
            assert(D18Transition(&card, 1, 2) == 2);
            assert(D18Transition(&card, 2, D18InheritAppearance) == 0);
            // Reusing an unmarked menu restores its native state; notification
            // policy does not leak into unrelated menus or app controllers.
            assert(D18Transition(&card, 0, 0) == requested && !card.managed);
        }
    }
    uint64_t reply = D18PreviewReply(UINT32_MAX, D18PreviewSubmitted);
    assert(reply >> 8 == UINT32_MAX && (reply & 0xff) == D18PreviewSubmitted);
    assert(D18PreviewReply(17, D18PreviewFailed) != D18PreviewReply(18, D18PreviewFailed));
    puts("PASS: process isolation, UI scope, stable preferences, Quick Actions-only fourth choice, invalid-value rejection, Default restoration, native-style transitions, and preview reply identity");
    return 0;
}
