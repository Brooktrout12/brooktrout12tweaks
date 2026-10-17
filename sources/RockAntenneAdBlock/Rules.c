#include "Rules.h"
#include <string.h>
#include <strings.h>

const RABHostRule RABHostRules[] = {
    {"deliveryengine.adswizz.com", true},
    {"synchrobox.adswizz.com", false},
    {"doubleclick.net", true},
    {"googlesyndication.com", true},
    {"googleadservices.com", true},
    {"adition.com", true},
    {"smartadserver.com", true},
};
const size_t RABHostRuleCount = sizeof(RABHostRules) / sizeof(RABHostRules[0]);

bool RABIsAdHost(const char *host) {
    if (!host || !*host) return false;
    size_t n = strlen(host);
    if (n && host[n - 1] == '.') --n;
    for (size_t i = 0; i < RABHostRuleCount; ++i) {
        const RABHostRule *rule = &RABHostRules[i];
        size_t length = strlen(rule->host);
        if (n < length) continue;
        size_t offset = n - length;
        if (strncasecmp(host + offset, rule->host, length) != 0) continue;
        if (!offset || (rule->includeSubdomains && host[offset - 1] == '.')) return true;
    }
    return false;
}

