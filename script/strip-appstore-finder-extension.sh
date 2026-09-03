#!/bin/bash
# Historical helper — the Xcode phase "Embed Finder Menu (Direct only)" now owns this.
# AppStore / AppStoreDebug: omit FinderMenuExtension.appex
# Debug / Release: copy + codesign the appex into the app bundle.
echo "Use the Xcode build phase 'Embed Finder Menu (Direct only)' instead." >&2
exit 0
