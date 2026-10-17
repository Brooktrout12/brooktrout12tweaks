#pragma once
#include <stdbool.h>
#include <stddef.h>

// Explicit ad-service rules. Radio/CDN hosts are intentionally absent.
typedef struct { const char *host; bool includeSubdomains; } RABHostRule;
extern const RABHostRule RABHostRules[];
extern const size_t RABHostRuleCount;
bool RABIsAdHost(const char *host);

