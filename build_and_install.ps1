Write-Host "Starting Flutter build..."
cd C:\Users\KreshOS\Documents\00-Progetti\Fin
flutter build apk --flavor dev --release --no-tree-shake-icons
if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful, installing APK..."
    adb uninstall com.ecologicaleaving.fin.dev
    adb install build\app\outputs\flutter-apk\app-dev-release.apk
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Installation successful!"
        Get-ChildItem build\app\outputs\flutter-apk\app-dev-release.apk | Select-Object Name, Length, LastWriteTime
    } else {
        Write-Host "Installation failed!"
        exit 1
    }
} else {
    Write-Host "Build failed!"
    exit 1
}
