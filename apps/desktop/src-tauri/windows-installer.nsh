; Remove the previous current-user installation through its registered uninstaller.
; Run only after the new binary has been installed. The old silent uninstaller
; preserves app configuration and backups, which use the unchanged bundle ID.
!macro NSIS_HOOK_POSTINSTALL
  !define LEGACY_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Machine Party 模组管理器"
  ReadRegStr $0 HKCU "${LEGACY_KEY}" "InstallLocation"
  ${If} $0 != ""
    StrCpy $0 $0 -1 1
    ReadRegStr $1 HKCU "${LEGACY_KEY}" "MainBinaryName"
    ReadRegStr $2 HKCU "${LEGACY_KEY}" "UninstallString"
    ${If} $1 != "${MAINBINARYNAME}.exe"
    ${OrIf} $2 != '$\"$0\uninstall.exe$\"'
    ${OrIf} $0 == $INSTDIR
      Abort "Could not verify the previous installation directory."
    ${EndIf}
    ClearErrors
    ExecWait '"$0\uninstall.exe" /S _?=$0' $3
    ${If} ${Errors}
    ${OrIf} $3 != 0
    ${OrIf} ${FileExists} "$0\${MAINBINARYNAME}.exe"
      Abort "Could not complete the previous version uninstall."
    ${EndIf}
    Delete "$0\uninstall.exe"
    RMDir "$0"
  ${EndIf}
!macroend
