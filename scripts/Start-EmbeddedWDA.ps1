param(
 [Parameter(Mandatory)][string]$Ios,
 [Parameter(Mandatory)][string]$Udid,
 [Parameter(Mandatory)][string]$BundleId
)
$ErrorActionPreference='Stop'
# Prepare/mount the developer image first. Use the installed, re-signed main ID.
& $Ios "--udid=$Udid" runwda "--bundleid=$BundleId" "--testrunnerbundleid=$BundleId" `
 '--xctestconfig=../Frameworks/WebDriverAgentLib.framework' `
 '--env=DYLD_INSERT_LIBRARIES=/System/Developer/usr/lib/libXCTestBundleInject.dylib'
if($LASTEXITCODE -ne 0){throw '同梱WDAの起動に失敗しました。開発者モード・DDI・署名を確認してください。'}
