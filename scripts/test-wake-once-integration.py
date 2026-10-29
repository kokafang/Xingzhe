#!/usr/bin/env python3
"""Exercise real AppDelegate control flow with in-memory, power-free dependencies.

Generated code retains the production toggle/change/tick/cancellation methods and
launch callback wiring. Only UI rendering/building, startup/quit side effects and
dependency types are replaced. There is no NSApplication, SMAppService, IOKit,
production UserDefaults, XPC or system-power access in the compiled test program.
Source anchors are intentionally strict: refactors must update this adapter.
"""
from pathlib import Path
import subprocess
import re
import tempfile

root = Path(__file__).resolve().parent.parent
original = (root / "Sources/App/main.swift").read_text()
assert original.count('if CommandLine.arguments.contains("--repair-helper")') == 1
source = original.split('if CommandLine.arguments.contains("--repair-helper")')[0]
assert source.count('    @objc private func quitApp()') == 1
source = source.split('    @objc private func quitApp()')[0] + '}\n'
start = source.index('    func applicationDidFinishLaunching(')
end = source.index('    private func buildMenu()', start)
launch = source[start:end]
callbacks = launch[launch.index('        lidMonitor.onChange ='):launch.index('        if !UserDefaults.standard.bool')]
source = source[:start] + '    func installTestCallbacks() {\n' + callbacks + '    }\n\n' + source[end:]
start = source.index('    private func buildMenu()')
end = source.index('    @objc private func onceChanged()', start)
render_source = source[source.index('    private func render(', start):end]
# Keep the actual production state assignments: the test must catch two switches
# accidentally rendered on together, rather than reproducing expected logic.
switch_states = re.findall(r'^        (?:onceToggle|toggle)\.state = .+$', render_source, re.MULTILINE)
assert len(switch_states) == 2, "Expected two production switch state assignments"
source = source[:start] + ('    private var testMessage = ""\n'
    '    private func render(_ message: String? = nil) {\n'
    '        testMessage = message ?? ""\n' + '\n'.join(switch_states) + '\n    }\n\n') + source[end:]
source = source.replace('import AppKit\nimport ServiceManagement\n', 'import Foundation\n')
source = source.replace('NSObject, NSApplicationDelegate', 'NSObject')
for old, new in {
    'NSStatusItem': 'FakeStatusItem', 'NSSwitch': 'FakeSwitch',
    'NSTextField': 'FakeTextField', 'ServiceClient': 'FakeServiceClient',
    'IdleGuard': 'FakeIdleGuard', 'LidMonitor': 'FakeLidMonitor',
    'HelperRegistration': 'FakeHelperRegistration', 'UpdateController': 'FakeUpdateController',
    'SMAppService': 'FakeSMAppService', 'UserDefaults.standard': 'TestDefaults.standard',
}.items():
    source = source.replace(old, new)
source = '\n'.join(line for line in source.splitlines() if 'AwakeLog.' not in line)
for forbidden in ['import AppKit', 'import ServiceManagement', 'NSApp.', 'UserDefaults.standard', 'IOKit', 'AwakeLog.']:
    assert forbidden not in source, forbidden

fixture = (root / 'Tests/AppWakeOnce/Fixtures.swift.txt').read_text()
tests = (root / 'Tests/AppWakeOnce/Scenarios.swift.txt').read_text()
(root / 'build').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='app-wake-once-', dir=root / 'build') as folder:
    folder = Path(folder)
    main = folder / 'main.swift'
    main.write_text(fixture + '\n' + source + '\n' + tests)
    output = folder / 'AppWakeOnceTests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-module-cache-path', str(root / 'build/cache'),
                    str(root / 'Sources/Shared/WakeOnceSession.swift'),
                    str(root / 'Sources/Shared/ServiceTiming.swift'),
                    str(root / 'Sources/Shared/UpdatePreparation.swift'),
                    str(main), '-o', str(output)], check=True)
    subprocess.run([str(output)], check=True)
