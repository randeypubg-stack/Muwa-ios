from pathlib import Path
import subprocess, sys
root = Path(sys.argv[1])
build = Path('build')
source = (root/'Sources/Views/Player/FullPlayerView.swift').read_text()
geometry = source[source.index('struct PlayerGeometry {'):]
(build/'PlayerGeometry.swift').write_text('import Foundation\n'+geometry)
subprocess.run(['swiftc', '-parse-as-library', '-o', str(build/'audit-checks'),
 str(root/'Sources/Services/LibraryStore.swift'),
 str(root/'Sources/Models/Track.swift'), str(root/'Sources/Models/Publication.swift'),
 str(build/'PlayerGeometry.swift'), 'tests/AuditChecks.swift'], check=True)
subprocess.run([str(build/'audit-checks')], check=True)
