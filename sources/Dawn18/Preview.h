#pragma once
#include <stdint.h>

#define D18_PREVIEW_REQUEST "com.brooktrout12.dawn18/preview-request"
#define D18_PREVIEW_REPLY "com.brooktrout12.dawn18/preview-reply"
enum { D18PreviewSubmitted = 1, D18PreviewUnavailable = 2, D18PreviewFailed = 3 };
// On-demand failure stages, carried in the existing one-byte reply. These
// identify an unavailable runtime interface without writing a background log.
enum {
    D18PreviewDispatcherUnavailable = 10,
    D18PreviewSourceUnavailable = 11,
    D18PreviewDestinationsUnavailable = 12,
    D18PreviewClassesUnavailable = 13,
    D18PreviewContentUnavailable = 14,
    D18PreviewOptionsUnavailable = 15,
    D18PreviewActionUnavailable = 16,
    D18PreviewRequestUnavailable = 17,
    D18PreviewRoutingUnavailable = 18,
    D18PreviewClearRequestsUnavailable = 19,
    D18PreviewClearDestinationsUnavailable = 20,
    D18PreviewClearSectionsUnavailable = 21,
    D18PreviewClearRangeUnavailable = 22,
    D18PreviewLookupUnavailable = 23
};

// A random request ID prevents a Settings pane from accepting an old reply.
static inline uint64_t D18PreviewReply(uint32_t request, unsigned int status) {
    return ((uint64_t)request << 8) | (status & 0xffu);
}
void D18StartNotificationPreview(void);
