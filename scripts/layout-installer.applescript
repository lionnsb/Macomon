on run argv
    set volumeName to item 1 of argv
    set mountPath to item 2 of argv
    set mountedVolume to (POSIX file mountPath) as alias

    tell application "Finder"
        open mountedVolume
        delay 1
        tell disk volumeName
            open
            set installerWindow to container window
            set current view of installerWindow to icon view
            set toolbar visible of installerWindow to false
            set statusbar visible of installerWindow to false
            set bounds of installerWindow to {120, 120, 840, 560}

            set viewOptions to icon view options of installerWindow
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 128
            set text size of viewOptions to 14
            set background picture of viewOptions to file ".background:dmg-background.png"

            -- Die Zielkästen im 1440×880-Retina-Hintergrund werden im Finder
            -- mit 720×440 Punkten dargestellt. Ihre Mittelpunkte liegen hier.
            set position of item "Macomon.app" to {227, 198}
            set position of item "Programme" to {492, 198}
            update without registering applications
            delay 2
            close installerWindow
        end tell
    end tell
end run
