#include "WarningRules.h"
#include <string.h>

bool BC18WarningText(const char *n) {
    if (!n) return false;
    static const char *const tokens[] = {
        "importantbatterymessage", "batteryhealthimportantmessage",
        "wichtigebatterienachricht", "wichtigebatteriemeldung",
        "nongenuinebattery", "unverifiedbattery", "batteryverification",
        "batteryauthentication", "batteryauthenticity", "unknownbattery"
    };
    for (size_t i = 0; i < sizeof(tokens) / sizeof(tokens[0]); ++i)
        if (strstr(n, tokens[i])) return true;
    return (strstr(n, "unabletoverify") && strstr(n, "battery"))
        || (strstr(n, "batterie") && (strstr(n, "nichtuberpruft")
            || strstr(n, "nichtverifiziert")));
}

bool BC18LearnMoreText(const char *n) {
    return n && (!strcmp(n, "learnmore") || !strcmp(n, "moreinformation")
        || !strcmp(n, "weitereinformationen") || !strcmp(n, "mehrerfahren"));
}

void BC18PlanWarningRemoval(const unsigned char *flags, size_t count,
                           unsigned char *actions) {
    if (!count) return;
    memset(actions, BC18Keep, count);
    for (size_t start = 0; start < count;) {
        size_t end = start + 1;
        while (end < count && !(flags[end] & BC18Group)) ++end;
        bool warning = false, protected = false;
        for (size_t i = start; i < end; ++i) {
            warning |= !!(flags[i] & BC18Warning);
            protected |= !!(flags[i] & BC18Protected);
        }
        if (warning && !protected) {
            for (size_t i = start; i < end; ++i) actions[i] = BC18Remove;
        } else if (warning) {
            for (size_t i = start; i < end; ++i) {
                if ((flags[i] & BC18Protected) || !(flags[i] & BC18Warning)) continue;
                actions[i] = flags[i] & BC18Group ? BC18ClearGroup : BC18Remove;
            }
            /* A generic Learn More link in a mixed section could belong to
               another setting; leave it unless its own content is a warning. */
        }
        start = end;
    }
}
