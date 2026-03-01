#!/bin/bash
cd /c/Users/KreshOS/Documents/00-Progetti/Fin
echo "Starting Flutter build..."
flutter build apk --flavor dev --release --no-tree-shake-icons 2>&1
BUILD_EXIT=$?
echo "Build exited with code: $BUILD_EXIT"
if [ -f "build/app/outputs/flutter-apk/app-dev-release.apk" ]; then
    echo "APK created successfully"
    ls -lh build/app/outputs/flutter-apk/app-dev-release.apk
else
    echo "APK not created"
fi
exit $BUILD_EXIT
