#!/usr/bin/env python3
"""Patch project.pbxproj Release configs for manual Distribution signing in CI.

Usage:
    python3 patch_signing.py <main_uuid> <widgets_uuid> <watch_uuid> <watch_widgets_uuid>

Writes CODE_SIGN_STYLE=Manual, CODE_SIGN_IDENTITY="Apple Distribution", and
PROVISIONING_PROFILE_SPECIFIER=<uuid> into the four app-target Release build
configurations (BC000004/10/12/14).  SPM package targets live in DerivedData
(not in project.pbxproj), so they keep their own Automatic signing and never
conflict with the Distribution identity.
"""
import sys

config_profiles = {
    'BC000004': sys.argv[1],   # DailyOK (main app)
    'BC000010': sys.argv[2],   # DailyOKWidgets
    'BC000012': sys.argv[3],   # DailyOKWatch
    'BC000014': sys.argv[4],   # DailyOKWatchWidgets
}

with open('DailyOK.xcodeproj/project.pbxproj', 'r') as f:
    lines = f.readlines()

result = []
current_config = None
in_build_settings = False
injected = False

for line in lines:
    stripped = line.strip()

    # Detect entering a Release config we want to patch.
    if not current_config:
        for config_id in config_profiles:
            if f'{config_id} /* Release */' in line:
                current_config = config_id
                in_build_settings = False
                injected = False
                break

    skip = False
    if current_config and in_build_settings:
        s = stripped
        # Remove existing signing settings we are about to inject explicitly.
        # Guard CODE_SIGN_IDENTITY check so we don't drop CODE_SIGN_ENTITLEMENTS.
        if (s.startswith('CODE_SIGN_STYLE =') or
                s.startswith('PROVISIONING_PROFILE_SPECIFIER =') or
                (s.startswith('CODE_SIGN_IDENTITY =') and 'ENTITLEMENTS' not in s)):
            skip = True
        # Exit the buildSettings dict on its closing brace.
        if s == '};':
            in_build_settings = False

    if not skip:
        result.append(line)

    if current_config:
        # Right after buildSettings = {, inject our per-target signing triple.
        if stripped == 'buildSettings = {':
            in_build_settings = True
            if not injected:
                uuid = config_profiles[current_config]
                t = '\t\t\t\t'
                result.append(f'{t}CODE_SIGN_IDENTITY = "Apple Distribution";\n')
                result.append(f'{t}CODE_SIGN_STYLE = Manual;\n')
                result.append(f'{t}PROVISIONING_PROFILE_SPECIFIER = "{uuid}";\n')
                injected = True
        # Exit this configuration object after its name property.
        if stripped == 'name = Release;':
            current_config = None
            in_build_settings = False

with open('DailyOK.xcodeproj/project.pbxproj', 'w') as f:
    f.writelines(result)

print('Patched project.pbxproj with per-target manual Distribution signing')
