#import "IOS17Sections.h"
#import "Runtime.h"
#import <substrate.h>
#include <pthread.h>

static Class CQA17ListClass;
static Class CQA17SectionClass;
static CQAIconMenuPolicy CQA17Policy;
static BOOL (*CQA17OriginalWantsSeparator)(id, SEL);
static char CQA17OwnerKey, CQA17LastPolicyKey;

static BOOL CQA17WantsSeparator(id self, SEL cmd) {
    BOOL native = CQA17OriginalWantsSeparator(self, cmd);
    if (!native || !pthread_main_np()) return native;
    NSHashTable<UIView *> *owners = objc_getAssociatedObject(self, &CQA17OwnerKey);
    UIView *owner = owners.anyObject;
    // A weak owner avoids retaining a dismissed menu. Recheck its current
    // scope and the switch on every read; never overwrite UIKit's model value.
    return owner && CQA17Policy(owner) ? NO : native;
}

void CQAInstallIOS17SectionFix(CQAIconMenuPolicy policy) {
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 17 ||
        !policy || CQA17SectionClass) return;
    Class section = NSClassFromString(@"_UIContextMenuSection");
    Class list = NSClassFromString(@"_UIContextMenuListView");
    SEL wants = NSSelectorFromString(@"wantsSectionSeparator");
    if (![list isSubclassOfClass:UIView.class] ||
        !CQAMethodMatches(list, NSSelectorFromString(@"collectionView"), '@', "") ||
        !CQAMethodMatches(list, NSSelectorFromString(@"collectionViewDataSource"), '@', "") ||
        !(CQAMethodMatches(section, wants, 'B', "") ||
          CQAMethodMatches(section, wants, 'c', ""))) return;
    CQA17Policy = policy;
    CQA17ListClass = list;
    CQA17SectionClass = section;
    MSHookMessageEx(section, wants, (IMP)CQA17WantsSeparator,
                   (IMP *)&CQA17OriginalWantsSeparator);
}

void CQARefreshIOS17Sections(UIView *view) {
    if (!CQA17SectionClass || !pthread_main_np() ||
        ![view isKindOfClass:CQA17ListClass]) return;
    id source = CQAGetObject(view, NSSelectorFromString(@"collectionViewDataSource"));
    id collection = CQAGetObject(view, NSSelectorFromString(@"collectionView"));
    if (![source isKindOfClass:UICollectionViewDiffableDataSource.class] ||
        ![collection isKindOfClass:UICollectionView.class]) return;

    BOOL active = CQA17Policy(view);
    BOOL changed = NO;
    NSArray *sections = [(UICollectionViewDiffableDataSource *)source snapshot].sectionIdentifiers;
    for (id section in sections) {
        if (![section isKindOfClass:CQA17SectionClass]) continue;
        NSHashTable<UIView *> *owners = objc_getAssociatedObject(section, &CQA17OwnerKey);
        if (!owners && !active) continue; // Leave unrelated menus untouched.
        NSNumber *previous = objc_getAssociatedObject(section, &CQA17LastPolicyKey);
        if (!owners) {
            owners = [NSHashTable weakObjectsHashTable];
            objc_setAssociatedObject(section, &CQA17OwnerKey, owners,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (owners.anyObject != view || !previous || previous.boolValue != active) {
            [owners removeAllObjects];
            [owners addObject:view];
            objc_setAssociatedObject(section, &CQA17LastPolicyKey, @(active),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            changed = YES;
        }
    }
    if (changed) {
        // UIKit may already have cached section decorations before the menu
        // received its icon-owner marker. Recompute only when policy/ownership
        // changes, not on every layout. Native cell sizing remains in charge.
        [[(UICollectionView *)collection collectionViewLayout] invalidateLayout];
        [view setNeedsLayout];
    }
}
