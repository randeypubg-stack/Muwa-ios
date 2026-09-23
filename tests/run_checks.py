from pathlib import Path
import subprocess, sys
root = Path(sys.argv[1])
build = Path('build')
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
