from pathlib import Path
import subprocess, sys
root = Path(sys.argv[1])
build = Path('build')
build.mkdir(exist_ok=True)
source = (root/'Sources/Views/Player/FullPlayerView.swift').read_text()
geometry = source[source.index('struct PlayerGeometry {'):].split('\nprivate struct PlaybackScrubber:')[0]
(build/'PlayerGeometry.swift').write_text('import Foundation\n'+geometry)
subprocess.run(['swiftc', '-parse-as-library', '-o', str(build/'audit-checks'),
 str(root/'Sources/Services/LibraryStore.swift'),
 str(root/'Sources/Models/Track.swift'), str(root/'Sources/Models/Publication.swift'),
 str(build/'PlayerGeometry.swift'), 'tests/AuditChecks.swift'], check=True)
subprocess.run([str(build/'audit-checks')], check=True)

player = (root/'Sources/Services/PlayerManager.swift').read_text()
clock = '@MainActor\n' + player[player.index('final class PlaybackTimeline:'):]
(build/'PlaybackTimeline.swift').write_text('import Foundation\nimport Combine\n'+clock)
subprocess.run(['swiftc', '-parse-as-library', '-o', str(build/'timeline-checks'),
 str(build/'PlaybackTimeline.swift'), 'tests/TimelineChecks.swift'], check=True)
subprocess.run([str(build/'timeline-checks')], check=True)

subprocess.run(['swiftc', '-parse-as-library', '-o', str(build/'ai-subtitle-checks'),
 str(root/'Sources/Models/SubtitleModels.swift'), 'tests/AISubtitleChecks.swift'], check=True)
subprocess.run([str(build/'ai-subtitle-checks')], check=True)

subprocess.run(['swiftc', '-parse-as-library', '-o', str(build/'premium-account-checks'),
 str(root/'Sources/Services/PremiumManager.swift'), str(root/'Sources/Services/BackendConfig.swift'),
 'tests/PremiumAccountChecks.swift'], check=True)
subprocess.run([str(build/'premium-account-checks')], check=True)

launch = (root/'Sources/App/LaunchExperience.swift').read_text().split('\nstruct MuwaLaunchView:')[0]
(build/'LaunchPresentation.swift').write_text(launch.replace('import SwiftUI', 'import Foundation\nimport Combine'))
subprocess.run(['swiftc', '-parse-as-library', '-o', str(build/'launch-checks'),
 str(build/'LaunchPresentation.swift'), 'tests/LaunchChecks.swift'], check=True)
subprocess.run([str(build/'launch-checks')], check=True)

# Test-only diagnostics sink; these executables do not link MetricKit or ship.
(build/'AuditDiagnostics.swift').write_text('import Foundation\n@MainActor final class Diagnostics { static let shared = Diagnostics(); func record(_ area: String, error: Error) {} }\n')
for executable, sources, check in [
    ('auth-checks', ['Services/AuthManager.swift', 'Services/AuthService.swift', 'Services/BackendConfig.swift', 'Models/AuthUser.swift'], 'tests/AuthChecks.swift'),
    ('download-checks', ['Services/DownloadManager.swift', 'Models/Track.swift'], 'tests/DownloadChecks.swift'),
]:
    subprocess.run(['swiftc', '-parse-as-library', '-o', str(build/executable),
        *[str(root/'Sources'/source) for source in sources], str(build/'AuditDiagnostics.swift'), check], check=True)
    subprocess.run([str(build/executable)], check=True)
