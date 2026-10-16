#!/usr/bin/env python3
from pathlib import Path
import plistlib, shutil, subprocess, hashlib
R=Path(__file__).resolve().parent; P=R/'package'; D=P/'DEBIAN';D.mkdir(parents=True,exist_ok=True)
label='com.chatgpt.jbbatterywatch'
common='''#!/var/jb/bin/sh
set -eu
PATH=/var/jb/usr/sbin:/var/jb/usr/bin:/var/jb/sbin:/var/jb/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
LABEL=com.chatgpt.jbbatterywatch
PLIST=/var/jb/Library/LaunchDaemons/com.chatgpt.jbbatterywatch.plist
REPORT=/var/mobile/Documents/JBBatteryReport-v2
STATE=/var/jb/var/lib/jb-battery-watch
find_launchctl() {
    for candidate in /bin/launchctl /var/jb/bin/launchctl /var/jb/usr/bin/launchctl; do
        if [ -x "$candidate" ]; then LC=$candidate; return 0; fi
    done
    LC=$(command -v launchctl || :)
    [ -n "$LC" ]
}
'''
# A stop must be verified when an existing job is running. Do not use pkill patterns.
stop='''stop_own_job() {
    if ! find_launchctl; then
        echo "ERROR: launchctl unavailable; cannot safely stop JB Battery Watch."
        return 1
    fi
    "$LC" bootout "system/$LABEL" >> "$STATE/lifecycle.log" 2>&1 ||
        "$LC" unload "$PLIST" >> "$STATE/lifecycle.log" 2>&1 || :
    if "$LC" print "system/$LABEL" > /dev/null 2>&1; then
        echo "ERROR: JB Battery Watch job is still registered; stop was not verified."
        return 1
    fi
}
'''
preinst=common+stop+'''case "${1:-}" in
    install|upgrade)
        mkdir -p "$STATE"
        chmod 0700 "$STATE"
        stop_own_job
        # Preserve a v2 recording when installing the Settings upgrade. A root
        # marker is used only by our own maintainer scripts, never by the UI.
        case "${2:-}" in
            2.*)
                if [ -f "$STATE/session.bin" ] || [ -f "$STATE/completed" ]; then
                    : > "$STATE/preserve-upgrade"
                    rm -f "$STATE/new-install"
                else
                    : > "$STATE/new-install"
                fi
                ;;
            *) : > "$STATE/new-install" ;;
        esac
        ;;
esac
exit 0
'''
postinst=common+'''case "${1:-}" in configure) ;; *) exit 0 ;; esac
mkdir -p "$STATE" /var/mobile/Documents
chmod 0700 "$STATE"
if [ -f "$STATE/new-install" ]; then
    # Keep prior reports. No v1 report files or tweak settings are removed.
    if [ -d "$REPORT" ]; then
        PREVIOUS="$REPORT-previous-$(date +%s)-$$"
        mv "$REPORT" "$PREVIOUS"
    fi
    rm -f "$STATE/session.bin" "$STATE/session.bin.tmp" "$STATE/completed"
    rm -f "$STATE/new-install"
fi
mkdir -p "$REPORT"
chown 0:501 "$REPORT"
chmod 0750 "$REPORT"
LOG="$REPORT/INSTALL.txt"
: > "$LOG"
chown 0:501 "$LOG"
chmod 0640 "$LOG"
fail_recording() {
    printf 'JB Battery Watch 2.1.1\nERROR: %s\n\nRecording has NOT started.\nShare INSTALL.txt and PROBE.txt from this folder.\n' "$1" > "$REPORT/STATUS.txt"
    chown 0:501 "$REPORT/STATUS.txt"
    chmod 0640 "$REPORT/STATUS.txt"
    printf '<?xml version="1.0"?><plist version="1.0"><dict><key>Schema</key><integer>1</integer><key>State</key><string>ERROR</string><key>Message</key><string>Installation or startup failed. See Diagnostic Details and export the report.</string></dict></plist>\n' > "$REPORT/HEALTH.plist"
    chown 0:501 "$REPORT/HEALTH.plist"
    chmod 0640 "$REPORT/HEALTH.plist"
    echo "JB Battery Watch: $1 -- see $REPORT/STATUS.txt"
    # Remain installed so logs are readable and uninstall remains straightforward.
    exit 0
}
if ! find_launchctl; then fail_recording "launchctl could not be found"; fi
if [ -f "$STATE/preserve-upgrade" ]; then
    echo "Existing v2 report and session are preserved; the collector resumes the original deadline." >> "$LOG"
    rm -f "$STATE/preserve-upgrade"
fi
printf 'JB Battery Watch 2.1.1\nSTARTING: Checking native API access before recording.\n' > "$REPORT/STATUS.txt"
chown 0:501 "$REPORT/STATUS.txt"
chmod 0640 "$REPORT/STATUS.txt"
if /var/jb/usr/libexec/jb-battery-watch --probe >> "$LOG" 2>&1; then
    echo "Native API probe succeeded." >> "$LOG"
else
    fail_recording "native probe failed (launch/signing/permissions/API availability)"
fi
if "$LC" bootstrap system "$PLIST" >> "$LOG" 2>&1; then
    echo "launchctl bootstrap succeeded." >> "$LOG"
elif "$LC" load "$PLIST" >> "$LOG" 2>&1; then
    echo "launchctl legacy load succeeded." >> "$LOG"
else
    fail_recording "launchd rejected the diagnostic job"
fi
# Check actual status, not just launchctl's registration result. This is a bounded
# install-time wait only, not a persistent polling/wake daemon.
i=0
while [ "$i" -lt 15 ]; do
    if grep -Eq '^(RECORDING|COMPLETE|ERROR|STOPPED)' "$REPORT/STATUS.txt"; then break; fi
    sleep 1
    i=$((i + 1))
done
if ! grep -Eq '^(RECORDING|COMPLETE|ERROR|STOPPED)' "$REPORT/STATUS.txt"; then
    "$LC" print "system/$LABEL" >> "$LOG" 2>&1 || :
    "$LC" bootout "system/$LABEL" >> "$LOG" 2>&1 || :
    fail_recording "recorder did not confirm startup; job was asked to stop"
fi
echo "JB Battery Watch installed. Open Settings > JB Battery Watch > Check Now."
echo "Use Export Full Report in the Settings pane to share logs and diagnostics."
exit 0
'''
prerm=common+stop+'''case "${1:-}" in
    remove|upgrade|deconfigure)
        mkdir -p "$STATE"
        chmod 0700 "$STATE"
        stop_own_job
        ;;
esac
exit 0
'''
postrm=common+'''case "${1:-}" in
    purge)
        # Reports are user data and deliberately retained, even on purge.
        rm -f "$STATE/session.bin" "$STATE/session.bin.tmp" "$STATE/completed" "$STATE/collector.lock" "$STATE/new-install" "$STATE/preserve-upgrade" "$STATE/lifecycle.log"
        rmdir "$STATE" 2>/dev/null || :
        ;;
esac
exit 0
'''
for name,content in [('preinst',preinst),('postinst',postinst),('prerm',prerm),('postrm',postrm)]:
    p=D/name;p.write_text(content);p.chmod(0o755);subprocess.run(['sh','-n',str(p)],check=True)
control='''Package: com.chatgpt.jbbatterywatch
Name: JB Battery Watch
Version: 2.1.1
Architecture: iphoneos-arm64
Maintainer: JB Battery Watch experimental build
Author: OpenAI ChatGPT
Section: Tweaks
Priority: optional
Pre-Depends: bash, coreutils, grep
Depends: firmware (>= 15.0), preferenceloader, com.opa334.libsandy (>= 1.1)
Description: Experimental passive rootless battery/process diagnostic recorder
 Targeted at iPhone SE (2020) on iOS 17.6.x with Dopamine rootless.
 Adds a native Settings pane, live sample check and share-sheet export.
 Existing v2 reports and session deadlines are preserved on upgrade.
 Native arm64 recorder. Starts after a successful installation probe, writes
 one shareable text report, and stops after a 24-hour observation window.
 Includes process counters, battery snapshots, package inventory and
 declared injection candidates. Not an exact per-tweak energy profiler.
 No network upload. No tweak disabling. Not validated on a physical device.
'''
(D/'control').write_text(control)
exe=P/'var/jb/usr/libexec/jb-battery-watch';exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/'build/jb-battery-watch',exe);exe.chmod(0o755)
plist=P/'var/jb/Library/LaunchDaemons'/f'{label}.plist';plist.parent.mkdir(parents=True,exist_ok=True)
# One startup per launchd load, no unconditional KeepAlive / recurring wake schedule.
data={'Label':label,'ProgramArguments':['/var/jb/usr/libexec/jb-battery-watch'],'UserName':'root','GroupName':'wheel','RunAtLoad':True,'Nice':10,'ProcessType':'Background','LowPriorityIO':True,'ExitTimeOut':20,'StandardOutPath':'/var/mobile/Documents/JBBatteryReport-v2/LAUNCH.txt','StandardErrorPath':'/var/mobile/Documents/JBBatteryReport-v2/LAUNCH.txt','EnvironmentVariables':{'PATH':'/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin','_MSSafeMode':'1','_SafeMode':'1'}}
plist.write_bytes(plistlib.dumps(data));plist.chmod(0o644)
for p in P.rglob('*'):
    if p.is_dir():p.chmod(0o755)
print('Prepared package staging:',P)

# PreferenceLoader entry and sandbox-scoped read access. No broad filesystem
# extension, command helper, setuid executable, or SpringBoard hook is added.
bundle=P/'var/jb/Library/PreferenceBundles/JBBatteryWatchPrefs.bundle'
bundle.mkdir(parents=True,exist_ok=True)
shutil.copy2(R/'build/JBBatteryWatchPrefs',bundle/'JBBatteryWatchPrefs')
(bundle/'JBBatteryWatchPrefs').chmod(0o755)
(bundle/'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleDevelopmentRegion':'en','CFBundleExecutable':'JBBatteryWatchPrefs',
    'CFBundleIdentifier':'com.chatgpt.jbbatterywatch.preferences',
    'CFBundleName':'JB Battery Watch','CFBundlePackageType':'BNDL',
    'CFBundleVersion':'2.1.1','CFBundleShortVersionString':'2.1.1',
    'NSPrincipalClass':'JBBWPreferencesController','MinimumOSVersion':'15.0'}))
entry=P/'var/jb/Library/PreferenceLoader/Preferences/JBBatteryWatch.plist'
entry.parent.mkdir(parents=True,exist_ok=True)
entry.write_bytes(plistlib.dumps({'entry':{'bundle':'JBBatteryWatchPrefs','cell':'PSLinkCell',
    'detail':'JBBWPreferencesController','isController':True,'label':'JB Battery Watch'}}))
profile=P/'var/jb/Library/libSandy/JBBatteryWatch_ReadReports.plist'
profile.parent.mkdir(parents=True,exist_ok=True)
profile.write_bytes(plistlib.dumps({'AllowedProcesses':['com.apple.Preferences'],
    'Extensions':[{'type':'file','extension_class':'com.apple.app-sandbox.read',
                   'path':'/var/mobile/Documents/JBBatteryReport-v2'}]}))
