# ROCK ANTENNE AdBlock – Test 2

Rootless-Tweak für die offizielle ROCK ANTENNE-App auf iOS 17.x und 18.x. Version **0.2.0**, Paket-ID `com.brooktrout12.rockantenneadblock`.

Test 2 ergänzt die bisherigen Filter um die dokumentierte AdsWizz-Steuerung. Die Version ist gebaut und lokal geprüft, aber noch nicht auf einem iPhone getestet.

## Installation

1. `RockAntenneAdBlock_0.2.0_Test2_rootless.deb` mit deinem Paketmanager oder Filza installieren. Die gleiche Paket-ID ersetzt Test 1.
2. ROCK ANTENNE vollständig aus dem App-Umschalter schließen und neu öffnen. Einen vom Paketmanager verlangten Respring durchführen.
3. Sender starten und beobachten, was tatsächlich zu hören ist: direkter Livestream, Werbung vor dem Livestream oder ein Wiedergabefehler.

App-Daten müssen für das Update nicht gelöscht werden. Es gibt keinen zusätzlichen Schalter in den iOS-Einstellungen. Benötigt wird ein vorhandener Rootless-Jailbreak mit aktiver Tweak-Injection. RootHide und Rootful sind nicht Teil dieses Pakets.

## Was Test 2 ändert

AdsWizz stellt über seinen öffentlichen `AdManager` die Methode `skipAd` bereit. Der Tweak erkennt passende Klassen anhand der geladenen SDK-Protokolle und prüft vor Eingriffen die Objective-C-Methodensignaturen. Er beobachtet Werbebeginn und Werbeereignisse und fordert das Überspringen über diese SDK-Funktion an. Auch der Aufruf zum Abspielen einer SDK-Anzeige wird nach Möglichkeit abgefangen.

Der normale SDK-Ablauf bleibt zuständig für das Ende der Werbung und den Übergang zum Stream. Vorhandene Delegate-Aufrufe werden weitergereicht. Doppelte Anforderungen werden zusammengefasst; veraltete Anforderungen nach einem gemeldeten Werbeende werden verworfen. Pro AdManager sind höchstens zwölf Aufrufe vorgesehen, damit kein unbegrenzter Wiederholungszyklus entsteht.

**AdsWizz-Delivery-Anfragen werden nativ durchgelassen, sobald passende Skip-Hooks installiert sind.** Solche Antworten können die Informationen enthalten, anhand derer der SDK eine bereits vorgeschaltete Anzeige identifiziert. Ein leeres VAST-Dokument kann diese Informationen entfernen, ohne die Werbung zu entfernen. Ob dieses Verhalten in einer bestimmten App-Version auftritt, muss auf dem Gerät geprüft werden.

Andere vorhandene Hostfilter und die WebKit-Regeln bleiben aktiv. Der offizielle Webplayer-Companion-Dialog wird weiterhin über seinen Schließen-Mechanismus geschlossen. Stream-Adressen, Lautstärke und normale AVPlayer-Wiedergabe werden nicht umgeschrieben.

## Diagnose direkt in der App

Die Diagnose läuft automatisch ab dem App-Start. **Zwei Finger gleichzeitig auf den Bildschirm der geöffneten ROCK ANTENNE-App legen und ungefähr zwei Sekunden ruhig liegen lassen.** Das Menü muss jetzt **„ROCK ANTENNE AdBlock · Test 2“** heißen.

Am besten während oder direkt nach dem Problem öffnen. Wähle das tatsächlich beobachtete Ergebnis:

- „Audio-Werbung melden & teilen“ bei hörbarer Werbung.
- „Banner/Popup melden & teilen“ bei sichtbarer Werbung.
- „Wiedergabefehler melden & teilen“ bei einem Hänger oder ausbleibender Wiedergabe.
- „Direkter Livestream ohne Werbung & teilen“ bei entsprechendem Höreindruck.

Der Bericht wird erst über deine Auswahl im Teilen-Menü weitergegeben. Er wird nicht automatisch hochgeladen. Weil Werbung selten ausgeliefert wird, beweist auch ein Start ohne Werbung für sich allein noch keine erfolgreiche Blockierung.

Neu protokolliert werden:

- SDK-Version, vorhandene Protokolle und tatsächlich installierte Hooks.
- `BREAK_STARTED`: Das SDK meldet einen Werbeblock.
- `SKIP_REQUEST` und `SKIP_CALL`: Überspringen angefordert beziehungsweise SDK-Methode aufgerufen.
- `BREAK_ENDED` und `SDK_WILL_RECONNECT`: Das SDK meldet das Ende beziehungsweise eine bevorstehende Wiederverbindung.
- AVPlayer-Zustand als `waiting`, `playing` oder `paused` sowie Wiedergabeposition nach 0,5, 2, 8 und 20 Sekunden, soweit der beobachtete Player noch denselben Inhalt verwendet.
- Anzahl von URL-Parametern und bekannten AdsWizz-Parametern, ausschließlich als Zahlen und ohne deren Inhalte.

**Keiner dieser Einzelwerte ist automatisch ein Beweis für werbefreies Hören.** Dafür werden zeitlicher Ablauf und dein Bericht zusammen ausgewertet. Zahlen wie `SDK_EVENT raw=…` werden bewusst ohne geratenen Ereignisnamen protokolliert.

Der Bericht enthält außerdem die bestehenden Host-/Web-Diagnosen, die Klassen der Oberfläche, relevante SDK-Klassen und das vorherige Startprotokoll. Cookies, HTTP-Header, Anfrageinhalte, URL-Parameterwerte, Audioaufnahmen und Bildschirmaufnahmen werden nicht gespeichert. Pro Start gilt ein Limit von ungefähr 256 KiB und 1.800 Einträgen.

Falls das Menü nicht erscheint: Die Dateien `RockAntenneAdBlock.log` und `RockAntenneAdBlock-Previous.log` liegen im **Documents-Ordner der ROCK ANTENNE-App**, sofern der Tweak geladen wurde. Bei einem Absturz ist zusätzlich der iOS-Absturzbericht hilfreich.

## Grenzen

Die neuen Eingriffe setzen voraus, dass die installierte App die dokumentierten Objective-C-Schnittstellen des AdsWizz-SDK benutzt. Installierte Hooks allein garantieren nicht, dass dieser Ausführungspfad tatsächlich verwendet wird. Fehlende oder unpassende Schnittstellen werden protokolliert; private Swift-Aufrufkonventionen werden nicht geraten.

Ein erst spät gemeldeter Werbebeginn kann zu einem kurzen hörbaren Anfang führen. Andere Werbeplayer und native Anzeigen können weitere Anpassungen brauchen. Werbeblöcke im normalen Radioprogramm werden nicht entfernt. Die Erkennung und das Verhalten der installierten App müssen auf dem Gerät geprüft werden.

Der Tweak lädt ausschließlich in `de.rockantenne.eple`. Native Filter decken die unterstützten URL-Ladeschnittstellen ab; direkte Socket-Verbindungen und Hintergrund-Download-Sessions sind darin nicht vollständig erfasst. WebKit-Regeln werden asynchron kompiliert. Cache, Anmeldedaten und App-Einstellungen werden nicht gelöscht.

## Rückgängig machen

Den Tweak über den Paketmanager deinstallieren, ROCK ANTENNE vollständig schließen und neu öffnen.

## Bauen und prüfen

```sh
make clean package THEOS=/pfad/zu/theos
cc -std=c11 -Wall -Wextra -Werror Rules.c tests/test_rules.c -o /tmp/rab-rules
/tmp/rab-rules
cc -std=c11 -Wall -Wextra -Werror SkipGate.c tests/test_skipgate.c -o /tmp/rab-skip
/tmp/rab-skip
python3 tests/test_webscript.py
python3 scripts/verify_package.py packages/com.brooktrout12.rockantenneadblock_0.2.0_iphoneos-arm64.deb
```

Der Webscript-Test benötigt Node.js. Build- und Prüfberichte stehen unter `validation/`. Sie prüfen unter anderem Paketumfang, Signatur, Hostgrenzen, die Regeln für ausstehende Skip-Aufrufe und das eingebettete JavaScript. Sie simulieren weder das echte AdsWizz-SDK noch ein iPhone. Quellen und Build-Details stehen in `BUILD-INFO.md`.

