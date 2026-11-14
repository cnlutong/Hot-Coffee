; Tauri's NSIS installation records use productName rather than bundle identifier.
; Remove only our previous-name installation, retaining its application data.
!define HOT_COFFEE_LEGACY_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Caffeine"
Var HotCoffeeLegacyDir

!macro NSIS_HOOK_PREINSTALL
  Push $0
  Push $1
  ReadRegStr $0 HKCU "${HOT_COFFEE_LEGACY_KEY}" "Publisher"
  ${If} $0 == "${MANUFACTURER}"
    ReadRegStr $0 HKCU "${HOT_COFFEE_LEGACY_KEY}" "MainBinaryName"
    ReadRegStr $HotCoffeeLegacyDir HKCU "Software\${MANUFACTURER}\Caffeine" ""
    ${If} $0 == "caffeine.exe"
    ${AndIf} $HotCoffeeLegacyDir != ""
      ${IfNot} ${FileExists} "$HotCoffeeLegacyDir\uninstall.exe"
        Abort "The previous installation is incomplete. Uninstall it while keeping application data, then run the Hot Coffee installer again."
      ${EndIf}
      DetailPrint "Upgrading the previous installation to Hot Coffee..."
      !insertmacro CheckIfAppIsRunning "$HotCoffeeLegacyDir\caffeine.exe" "Hot Coffee"
      ClearErrors
      ; /UPDATE explicitly prevents the previous uninstaller from deleting preferences.
      ExecWait '"$HotCoffeeLegacyDir\uninstall.exe" /S /UPDATE _?=$HotCoffeeLegacyDir' $1
      ${If} ${Errors}
      ${OrIf} $1 != 0
      ${OrIf} ${FileExists} "$HotCoffeeLegacyDir\caffeine.exe"
        Abort "Could not upgrade the previous installation. Close it and retry, or uninstall it while keeping application data."
      ${EndIf}

      ; /UPDATE leaves shortcuts intact. Remove only links targeting our old binary.
      !insertmacro IsShortcutTarget "$SMPROGRAMS\Caffeine.lnk" "$HotCoffeeLegacyDir\caffeine.exe"
      Pop $0
      ${If} $0 = 1
        !insertmacro UnpinShortcut "$SMPROGRAMS\Caffeine.lnk"
        Delete "$SMPROGRAMS\Caffeine.lnk"
      ${EndIf}
      !insertmacro IsShortcutTarget "$DESKTOP\Caffeine.lnk" "$HotCoffeeLegacyDir\caffeine.exe"
      Pop $0
      ${If} $0 = 1
        !insertmacro UnpinShortcut "$DESKTOP\Caffeine.lnk"
        Delete "$DESKTOP\Caffeine.lnk"
      ${EndIf}
      DeleteRegKey HKCU "Software\${MANUFACTURER}\Caffeine"
    ${EndIf}
  ${EndIf}
  Pop $1
  Pop $0
!macroend
