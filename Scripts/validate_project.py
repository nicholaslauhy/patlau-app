from pathlib import Path
import plistlib
import re
import struct
import sys

root = Path(__file__).resolve().parents[1]
swift_files = sorted(root.joinpath("PatLau").rglob("*.swift"))
test_swift_files = sorted(root.joinpath("PatLauTests").rglob("*.swift"))
ui_test_swift_files = sorted(root.joinpath("PatLauUITests").rglob("*.swift"))
required = {"StudentsView", "AttendanceView", "PaymentsView", "TrainingView", "MakeupView", "CoachAttendanceView", "ChatsView", "ReportsView", "SettingsView"}
combined = "\n".join(path.read_text(encoding="utf-8") for path in swift_files)
errors = []
for name in sorted(required):
    if not re.search(rf"\bstruct\s+{name}\b", combined): errors.append(f"Missing screen: {name}")
required_link_markers = {
    "/api/telegram-support-admins": "shared Telegram administrator API",
    "/api/telegram-support-admins/test": "Telegram delivery test API",
    'identityCommand = "/myid"': "consistent Telegram identity command",
    'static let path = "/open-in-app/chats"': "conversation Universal Link parser",
    'static let customScheme = "patlau"': "free-signing custom URL parser",
    ".onOpenURL": "foreground custom URL handling",
    "case supportConversation(String)": "native conversation navigation route",
}
for marker, description in required_link_markers.items():
    if marker not in combined:
        errors.append(f"Missing {description}: {marker}")
if "/api/support/telegram-admins" in combined:
    errors.append("The obsolete Telegram administrator API route is still referenced.")
for path in swift_files:
    text = path.read_text(encoding="utf-8")
    depth = 0
    in_string = False
    escaped = False
    for char in text:
        if in_string:
            if escaped: escaped = False
            elif char == "\\": escaped = True
            elif char == '"': in_string = False
            continue
        if char == '"': in_string = True
        elif char == "{": depth += 1
        elif char == "}": depth -= 1
        if depth < 0: break
    if depth != 0 or in_string: errors.append(f"Unbalanced Swift delimiters: {path.relative_to(root)}")

try:
    import tree_sitter
    import tree_sitter_swift
    parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
    for path in swift_files:
        stack = [parser.parse(path.read_bytes()).root_node]
        while stack:
            node = stack.pop()
            if node.type == "ERROR":
                errors.append(f"Swift parse error in {path.relative_to(root)} at {node.start_point}")
            stack.extend(node.children)
except ImportError:
    print("Optional tree-sitter Swift parser is unavailable; running structural checks only.")

info_plist = plistlib.loads(root.joinpath("PatLau", "Info.plist").read_bytes())
registered_schemes = {
    scheme.lower()
    for item in info_plist.get("CFBundleURLTypes", [])
    for scheme in item.get("CFBundleURLSchemes", [])
    if isinstance(scheme, str)
}
if "patlau" not in registered_schemes:
    errors.append("Info.plist does not register the patlau custom URL scheme.")
configuration = root.joinpath("PatLau", "Core", "AppConfiguration.swift").read_text(encoding="utf-8")
if "service_role" in configuration.lower(): errors.append("A service-role key must never be embedded in the app.")

app_icon = root.joinpath(
    "PatLau", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png"
)
if not app_icon.exists():
    errors.append("Missing 1024x1024 AppIcon.png.")
else:
    icon_data = app_icon.read_bytes()
    if len(icon_data) < 26 or icon_data[:8] != b"\x89PNG\r\n\x1a\n":
        errors.append("AppIcon.png must be a valid PNG file.")
    else:
        width, height = struct.unpack(">II", icon_data[16:24])
        color_type = icon_data[25]
        if (width, height) != (1024, 1024):
            errors.append("AppIcon.png must be exactly 1024x1024 pixels.")
        if color_type in (4, 6):
            errors.append("AppIcon.png must not contain an alpha channel.")

login_icon_set = root.joinpath("PatLau", "Assets.xcassets", "PatLauIcon.imageset")
for scale in (1, 2, 3):
    if not login_icon_set.joinpath(f"PatLauIcon-{scale}x.png").exists():
        errors.append(f"Missing login icon rendition: PatLauIcon-{scale}x.png")

project_file = root.joinpath("PatLau.xcodeproj", "project.pbxproj")
if not project_file.exists():
    errors.append("Missing Xcode project. Run `xcodegen generate`.")
else:
    project = project_file.read_text(encoding="utf-8")
    project_spec = root.joinpath("project.yml").read_text(encoding="utf-8")
    if "com.apple.developer.associated-domains" in project:
        errors.append("Personal Team builds must not request Associated Domains.")
    if "CODE_SIGN_ENTITLEMENTS" in project_spec:
        errors.append("XcodeGen still requests an entitlement file for the free-signing build.")
    for path in swift_files + test_swift_files + ui_test_swift_files:
        if f"{path.name} in Sources" not in project:
            errors.append(
                f"Swift source is not in an Xcode target: {path.relative_to(root)} "
                "(run `xcodegen generate`)"
            )
if errors:
    print("\n".join(f"ERROR: {item}" for item in errors)); sys.exit(1)
print(
    f"Validated {len(swift_files)} app, {len(test_swift_files)} unit-test, and "
    f"{len(ui_test_swift_files)} UI-test Swift source files, "
    "Xcode target membership, custom app links, Info.plist, required screens and secret-key guard."
)
