# Implementation references

The code in this project is original. The private method names and declarations
were checked against these references:

- [Apple: UIVisualEffectView](https://developer.apple.com/documentation/uikit/uivisualeffectview): live effects should not be made partially transparent through their view or an ancestor. The live effect and its ancestors remain at full alpha; outgoing transitions remove the material. Version 1.0.2 fades in by changing the effect itself from nil, with a separate title/border fade.

- [SBFluidSwitcherViewController runtime declarations](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBFluidSwitcherViewController.h): appLayouts, switcherController, visible-card access, native eligibility, lifecycle and gesture callbacks.
- [SBMainSwitcherControllerCoordinator runtime declarations](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBMainSwitcherControllerCoordinator.h): native display-item deletion, recent layouts, and dismissal to a selected app layout.
- [SBAppLayout declarations](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBAppLayout.h): allItems and homeScreenAppLayout.
- [SBDisplayItem declarations](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBDisplayItem.h): bundle and scene identity, equality, and the Home Screen marker.
- [Native app-closing example for iOS 16+](https://gist.github.com/MTACS/154b6b0a556932534f2356906e4981c7): killContainer:forReason: uses reason 0 for user closing. This project sends the native delegate callback for both visible and offscreen items instead of depending on existing card containers.
- [iOS 18.6 SpringBoard exports](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS18.6.sdk/System/Library/PrivateFrameworks/SpringBoard.framework/SpringBoard.tbd): confirms the fluid switcher, item container, coordinator and layout classes are present.

The method declarations are from iOS 17. Class exports do not establish method
behavior on their own, so runtime ABI checks remain in the release. Final visual
and functional validation must occur on the target iOS 18.6 phone.

Additional declarations used for 1.0.2 entry detection:

- [SBLayoutStateTransitionContext](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBLayoutStateTransitionContext.h): toLayoutState.
- [SBMainDisplayLayoutState](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBMainDisplayLayoutState.h): unlockedEnvironmentMode.
- [SBSwitcherTransitionRequest](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBSwitcherTransitionRequest.h): requestForActivatingAppSwitcher, requestForActivatingHomeScreen and unlockedEnvironmentMode.

Additional declarations checked for 1.0.5:

- [SBLayoutStateTransitionCoordinator](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBLayoutStateTransitionCoordinator.h): live isTransitioning and transitionContext getters.
- [SBLayoutStateTransitionContext](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBLayoutStateTransitionContext.h): isComplete as a fallback for a retained context.
- [SBSwitcherController](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBSwitcherController.h): layoutState and transition observer callbacks.
- The SBFluidSwitcherViewController declarations above also expose its own begin/end callbacks. Both levels are observed, with runtime signature guards, to obtain the actual view's live coordinator.

Inference: these getters allow readiness to be checked independently of whether
an earlier callback used the same context pointer. They do not establish the exact
ordering on every device. The user confirmed the resulting 1.0.5 behavior on
their iOS 18.6 phone; 1.0.6 removes its diagnostic trace.
