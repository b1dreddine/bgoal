"""Applies BGoal's settings to the android/ and ios/ projects made by `flutter create`.

Run from the app/ folder, after `flutter create` (see app/README.md):

    python tool/setup_platforms.py \
        --admob-android-app-id ca-app-pub-XXXXXXXXXXXXXXXX~NNNNNNNNNN \
        --admob-ios-app-id     ca-app-pub-XXXXXXXXXXXXXXXX~NNNNNNNNNN

Without the AdMob ids it uses Google's test app ids, which only show test ads:
fine for development, never for a store build. Safe to run again (for example after
adding google-services.json, or once you have the real AdMob ids): every step checks
what is already there. Needs only Python 3.9+, no packages.
"""
from __future__ import annotations

import argparse
import plistlib
import re
import shutil
import sys
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
DISPLAY_NAME = "BGoal"
SCHEME = "bgoal"
BRAND_GREEN = "#FF0E8A4A"
TEST_ANDROID_APP_ID = "ca-app-pub-3940256099942544~3347511713"
TEST_IOS_APP_ID = "ca-app-pub-3940256099942544~1458002511"
TRACKING_TEXT = (
    "Lets BGoal show ads that are more relevant to you. BGoal is free thanks to ads; "
    "you'll see ads either way."
)

done: list[str] = []
todo: list[str] = []


def note(changed: bool, what: str) -> None:
    done.append(("updated: " if changed else "already ok: ") + what)


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="\n")


def insert_after(text: str, anchor: str, addition: str, marker: str) -> tuple[str, bool]:
    """Adds [addition] right after [anchor] unless [marker] is already in the text."""
    if marker in text:
        return text, False
    i = text.find(anchor)
    if i < 0:
        raise LookupError(anchor)
    i += len(anchor)
    return text[:i] + addition + text[i:], True


# ---------------------------------------------------------------- Android


def android(admob_app_id: str, application_id: str | None) -> None:
    root = APP / "android"
    main = root / "app/src/main/AndroidManifest.xml"
    if not main.exists():
        sys.exit("android/ not found. Run `flutter create` first (see app/README.md).")

    m = read(main)
    changed = []

    # Release builds can't reach the backend without this: flutter create only puts it in debug.
    m, c = insert_after(
        m, 'xmlns:android="http://schemas.android.com/apk/res/android">',
        '\n    <uses-permission android:name="android.permission.INTERNET" />',
        "android.permission.INTERNET")
    changed.append(c)

    new = re.sub(r'android:label="[^"]*"', f'android:label="{DISPLAY_NAME}"', m, count=1)
    changed.append(new != m)
    m = new

    app_meta = (
        "\n        <!-- AdMob app id (AdMob: Apps, App settings). The app crashes at launch without it. -->"
        f'\n        <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="{admob_app_id}" />'
        "\n        <!-- Status-bar icon and colour for pushes shown by Firebase while the app is closed. -->"
        '\n        <meta-data android:name="com.google.firebase.messaging.default_notification_icon" android:resource="@drawable/ic_notification" />'
        '\n        <meta-data android:name="com.google.firebase.messaging.default_notification_color" android:resource="@color/bgoal_green" />'
    )
    if "com.google.android.gms.ads.APPLICATION_ID" in m:
        new = re.sub(
            r'(android:name="com\.google\.android\.gms\.ads\.APPLICATION_ID"\s+android:value=")[^"]*"',
            rf'\g<1>{admob_app_id}"', m)
        changed.append(new != m)
        m = new
    else:
        m, c = insert_after(m, 'android:icon="@mipmap/ic_launcher">', app_meta, "gms.ads.APPLICATION_ID")
        changed.append(c)

    deep_link = (
        '\n            <meta-data android:name="flutter_deeplinking_enabled" android:value="true" />'
        "\n            <intent-filter>"
        '\n                <action android:name="android.intent.action.VIEW" />'
        '\n                <category android:name="android.intent.category.DEFAULT" />'
        '\n                <category android:name="android.intent.category.BROWSABLE" />'
        f'\n                <data android:scheme="{SCHEME}" android:host="match" />'
        "\n            </intent-filter>"
    )
    launcher = '<category android:name="android.intent.category.LAUNCHER"/>\n            </intent-filter>'
    if launcher not in m:
        launcher = '<category android:name="android.intent.category.LAUNCHER" />\n            </intent-filter>'
    m, c = insert_after(m, launcher, deep_link, f'android:scheme="{SCHEME}"')
    changed.append(c)

    # Lets url_launcher open the privacy policy on Android 11+.
    m, c = insert_after(
        m, "<queries>",
        '\n        <intent>\n            <action android:name="android.intent.action.VIEW" />'
        '\n            <data android:scheme="https" />\n        </intent>',
        'android:scheme="https"')
    changed.append(c)
    write(main, m)
    note(any(changed), "AndroidManifest.xml (internet, name, AdMob id, notification icon, bgoal:// links)")

    # Local http backend during development only.
    debug = root / "app/src/debug/AndroidManifest.xml"
    if debug.exists():
        d = read(debug)
        if "usesCleartextTraffic" in d:
            note(False, "debug manifest allows http://")
        else:
            d = d.replace("</manifest>", '    <application android:usesCleartextTraffic="true" />\n</manifest>')
            write(debug, d)
            note(True, "debug manifest allows http:// (local backend)")

    res = root / "app/src/main/res"
    copied = False
    for src in (APP / "assets/brand/android").glob("drawable-*/ic_notification.png"):
        dst = res / src.parent.name / src.name
        if not dst.exists() or dst.read_bytes() != src.read_bytes():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
            copied = True
    note(copied, "notification icon (res/drawable-*/ic_notification.png)")

    colors = res / "values/bgoal_colors.xml"
    text = f'<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="bgoal_green">{BRAND_GREEN}</color>\n</resources>\n'
    note(not colors.exists() or read(colors) != text, "res/values/bgoal_colors.xml")
    write(colors, text)

    # Release builds strip resources only referenced by name: keep the notification icon.
    keep = res / "raw/keep.xml"
    text = ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@drawable/ic_notification" />\n')
    note(not keep.exists(), "res/raw/keep.xml (keeps the notification icon in release builds)")
    write(keep, text)

    gradle(root, application_id)


def gradle(root: Path, application_id: str | None) -> None:
    app_gradle = root / "app/build.gradle.kts"
    settings = root / "settings.gradle.kts"
    if not app_gradle.exists():
        todo.append("android/app/build.gradle is Groovy, not Kotlin: apply the Gradle steps in app/README.md by hand.")
        return

    g = read(app_gradle)
    changed = []

    # Imports go first; other statements only after the plugins {} block (a Gradle rule).
    if "keystoreProperties" not in g:
        g = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + g
        i = g.find("\nandroid {")
        if i < 0:
            raise LookupError("android {")
        g = (g[:i] + "\n// Release signing key, from android/key.properties (never commit it; see PUBLISHING.md).\n"
             "val keystoreProperties = Properties().apply {\n"
             '    val f = rootProject.file("key.properties")\n'
             "    if (f.exists()) load(FileInputStream(f))\n"
             "}\n" + g[i:])
        changed.append(True)

    has_services = (root / "app/google-services.json").exists()
    if has_services:
        g, c = insert_after(g, 'id("kotlin-android")', '\n    id("com.google.gms.google-services")', "com.google.gms.google-services")
        changed.append(c)
    else:
        todo.append("Add android/app/google-services.json (Firebase), then run this script again to enable the Google services plugin.")

    g, c = insert_after(g, "compileOptions {", "\n        isCoreLibraryDesugaringEnabled = true", "isCoreLibraryDesugaringEnabled")
    changed.append(c)

    new = re.sub(r"minSdk\s*=\s*[\w.]+", "minSdk = 26", g, count=1)
    changed.append(new != g)
    g = new

    if application_id:
        new = re.sub(r'applicationId\s*=\s*"[^"]*"', f'applicationId = "{application_id}"', g, count=1)
        changed.append(new != g)
        g = new

    signing = (
        "    signingConfigs {\n"
        '        create("release") {\n'
        '            keyAlias = keystoreProperties["keyAlias"] as String?\n'
        '            keyPassword = keystoreProperties["keyPassword"] as String?\n'
        '            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }\n'
        '            storePassword = keystoreProperties["storePassword"] as String?\n'
        "        }\n"
        "    }\n\n"
    )
    if 'create("release")' not in g:
        i = g.find("    buildTypes {")
        if i < 0:
            raise LookupError("buildTypes")
        g = g[:i] + signing + g[i:]
        changed.append(True)
    g = g.replace(
        "            // TODO: Add your own signing config for the release build.\n"
        "            // Signing with the debug keys for now, so `flutter run --release` works.\n", "")
    new = g.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        "// Debug keys until android/key.properties exists, so `flutter run --release` works.\n"
        "            signingConfig = signingConfigs.getByName(if (keystoreProperties.isEmpty) \"debug\" else \"release\")")
    changed.append(new != g)
    g = new

    if "desugar_jdk_libs" not in g:
        g = g.rstrip() + '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        changed.append(True)
    write(app_gradle, g)
    note(any(changed), "app/build.gradle.kts (minSdk 26, desugaring, release signing" + (", Google services" if has_services else "") + ")")

    if has_services and settings.exists():
        s = read(settings)
        s, c = insert_after(
            s, 'id("dev.flutter.flutter-plugin-loader") version "1.0.0"',
            '\n    id("com.google.gms.google-services") version "4.4.2" apply false',
            "com.google.gms.google-services")
        write(settings, s)
        note(c, "settings.gradle.kts (Google services plugin)")

    gitignore = root / ".gitignore"
    gi = read(gitignore) if gitignore.exists() else ""
    if "key.properties" not in gi:
        write(gitignore, gi.rstrip() + "\nkey.properties\n**/*.jks\n**/*.keystore\n")
        note(True, "android/.gitignore ignores key.properties and keystores")


# ---------------------------------------------------------------- iOS


def ios(admob_app_id: str, bundle_id: str | None) -> None:
    root = APP / "ios"
    plist_path = root / "Runner/Info.plist"
    if not plist_path.exists():
        todo.append("ios/ not found: run `flutter create --platforms ios .` (on any OS), then this script again.")
        return

    with plist_path.open("rb") as f:
        plist = plistlib.load(f)
    before = dict(plist)
    plist["CFBundleDisplayName"] = DISPLAY_NAME
    plist["CFBundleName"] = DISPLAY_NAME
    plist["GADApplicationIdentifier"] = admob_app_id
    # Google's own network id. Paste the full list from Google's iOS quick start
    # (developers.google.com/admob/ios/quick-start → "SKAdNetworkItems") for more ad demand.
    items = plist.get("SKAdNetworkItems", [])
    if not any(i.get("SKAdNetworkIdentifier") == "cstr6suwn9.skadnetwork" for i in items):
        items.insert(0, {"SKAdNetworkIdentifier": "cstr6suwn9.skadnetwork"})
    plist["SKAdNetworkItems"] = items
    plist["NSUserTrackingUsageDescription"] = TRACKING_TEXT
    plist["ITSAppUsesNonExemptEncryption"] = False
    plist["FlutterDeepLinkingEnabled"] = True
    types = plist.get("CFBundleURLTypes", [])
    if not any(SCHEME in t.get("CFBundleURLSchemes", []) for t in types):
        types.append({"CFBundleURLSchemes": [SCHEME]})
    plist["CFBundleURLTypes"] = types
    plist["CFBundleLocalizations"] = ["en", "fr", "ar"]
    modes = plist.get("UIBackgroundModes", [])
    if "remote-notification" not in modes:
        modes.append("remote-notification")
    plist["UIBackgroundModes"] = modes
    ats = plist.get("NSAppTransportSecurity", {})
    ats["NSAllowsLocalNetworking"] = True  # local backend during development; no effect on internet traffic
    plist["NSAppTransportSecurity"] = ats
    with plist_path.open("wb") as f:
        plistlib.dump(plist, f)
    note(plist != before, "Info.plist (name, AdMob id, tracking text, bgoal:// links, push, languages)")

    podfile = root / "Podfile"
    if podfile.exists():
        p = read(podfile)
        new = re.sub(r"^#?\s*platform :ios, '[\d.]+'", "platform :ios, '15.0'", p, count=1, flags=re.M)
        write(podfile, new)
        note(new != p, "Podfile (iOS 15)")

    pbx = root / "Runner.xcodeproj/project.pbxproj"
    if pbx.exists():
        x = read(pbx)
        new = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.0;", x)
        if bundle_id:
            new = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = [\w.\-]+\.RunnerTests;", f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id}.RunnerTests;", new)
            new = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = (?![\w.\-]+\.RunnerTests;)[\w.\-]+;", f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id};", new)
        write(pbx, new)
        note(new != x, "Xcode project (iOS 15 minimum" + (", bundle id" if bundle_id else "") + ")")

    privacy = root / "Runner/PrivacyInfo.xcprivacy"
    if not privacy.exists():
        shutil.copyfile(APP / "tool/ios/PrivacyInfo.xcprivacy", privacy)
        note(True, "Runner/PrivacyInfo.xcprivacy written")
    todo.append("In Xcode, drag ios/Runner/PrivacyInfo.xcprivacy into Runner (tick the Runner target) if it isn't listed there yet.")
    todo.append("In Xcode → Runner → Signing & Capabilities: your Team, then + Push Notifications and + Background Modes → Remote notifications.")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--admob-android-app-id", default=TEST_ANDROID_APP_ID)
    ap.add_argument("--admob-ios-app-id", default=TEST_IOS_APP_ID)
    ap.add_argument("--application-id", help="Android applicationId / iOS bundle id, if different from flutter create's")
    args = ap.parse_args()

    for value in (args.admob_android_app_id, args.admob_ios_app_id):
        if not re.fullmatch(r"ca-app-pub-\d{16}~\d{10}", value):
            sys.exit(f"{value!r} doesn't look like an AdMob app id (ca-app-pub-0000000000000000~0000000000).")

    android(args.admob_android_app_id, args.application_id)
    ios(args.admob_ios_app_id, args.application_id)

    print("\n".join(done))
    if args.admob_android_app_id == TEST_ANDROID_APP_ID or args.admob_ios_app_id == TEST_IOS_APP_ID:
        todo.insert(0, "Using Google's TEST AdMob app ids: fine for development, but run again with your real ids "
                       "before building for the stores.")
    if todo:
        print("\nStill to do:\n" + "\n".join(f"  - {t}" for t in todo))
    print("\nNext: dart run flutter_launcher_icons && dart run flutter_native_splash:create")


if __name__ == "__main__":
    main()
