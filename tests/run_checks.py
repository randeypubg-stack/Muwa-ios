from pathlib import Path
import subprocess, sys
root = Path(sys.argv[1])
build = Path('build')
source = (root/'Sources/Views/Player/FullPlayerView.swift').read_text()
small_actions_start = source.index('private var smallActions')
queue_action_start = source.index('Button {\n        queuePresented = true', small_actions_start)
subtitle_action = source[small_actions_start:queue_action_start]
assert 'premium.isPremium' not in subtitle_action, 'Subtitles must remain a standard feature'
assert 'lock.fill' not in subtitle_action, 'Standard subtitles must not show a Premium lock'
assert 'let coverScale: CGFloat = subtitleLayoutActive ? 0.82 : 1' in source
assert 'let railOffset = size * 0.47' in source
assert 'aiSubtitlesVisible' not in source, 'Do not maintain a second Premium-only subtitle mode'
premium_view = (root/'Sources/Views/Premium/PremiumView.swift').read_text()
assert 'Тексты\\nи переводы' not in premium_view, 'Subtitles/texts must not be advertised as Premium'
overlay = (root/'Sources/Views/Player/PlayerSubtitleOverlay.swift').read_text()
assert 'private struct AISubtitleRail' in overlay
assert 'offset(y: CGFloat(delta) * 58)' in overlay
assert '.background(LinearGradient' not in overlay.split('private struct AISubtitleRail')[1].split('private struct LegacySubtitleRail')[0]
player_manager = (root/'Sources/Services/PlayerManager.swift').read_text()
assert 'asset.load(.isPlayable)' in player_manager
assert 'loadValuesAsynchronously(forKeys:' not in player_manager
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
