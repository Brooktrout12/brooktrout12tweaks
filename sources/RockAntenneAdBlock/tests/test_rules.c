#include "../Rules.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    const char *blocked[] = {
        "rms.deliveryengine.adswizz.com", "deliveryengine.adswizz.com",
        "synchrobox.adswizz.com", "googleads.g.doubleclick.net",
        "pagead2.googlesyndication.com", "adservice.googleadservices.com",
        "ad1.adition.com", "www.smartadserver.com",
        "RMS.DELIVERYENGINE.ADSWIZZ.COM", "googleads.g.doubleclick.net."
    };
    const char *allowed[] = {
        "stream.rockantenne.de", "streams.rockantenne.de", "play.rockantenne.de",
        "stream.antenne.de", "s1-webradio.rockantenne.de", "www.rockantenne.de",
        "api.rockantenne.de", "antenne.de", "api.antenne.de",
        "rockantenne.hamburg", "rockantenne.bayern", "rockantenne.at",
        "sdk.mobile.streaming.adswizz.com", "streaming.adswizz.com", "adswizz.com",
        "podigee.io", "art19.com", "omnycontent.com", "api.spotify.com",
        "doubleclick.net.example.org", "notdoubleclick.net",
        "evildeliveryengine.adswizz.com", "synchrobox.adswizz.com.example.org",
        "different.synchrobox.adswizz.com", "", NULL
    };
    for (size_t i = 0; i < sizeof(blocked) / sizeof(*blocked); ++i) assert(RABIsAdHost(blocked[i]));
    for (size_t i = 0; i < sizeof(allowed) / sizeof(*allowed); ++i) assert(!RABIsAdHost(allowed[i]));
    printf("PASS: %zu blocked / %zu allowed host cases\n",
        sizeof(blocked) / sizeof(*blocked), sizeof(allowed) / sizeof(*allowed));
    return 0;
}
