LangString legacyDirectoryError 1033 "Could not verify the previous installation directory."
LangString legacyDirectoryError 2052 "无法验证旧版的安装目录。"
LangString legacyDirectoryError 1028 "無法驗證舊版的安裝目錄。"
LangString legacyUninstallError 1033 "Could not complete the previous version uninstall."
LangString legacyUninstallError 2052 "无法完成旧版的卸载。"
LangString legacyUninstallError 1028 "無法完成舊版的解除安裝。"

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
      Abort "$(legacyDirectoryError)"
    ${EndIf}
    ClearErrors
    ExecWait '"$0\uninstall.exe" /S _?=$0' $3
    ${If} ${Errors}
    ${OrIf} $3 != 0
    ${OrIf} ${FileExists} "$0\${MAINBINARYNAME}.exe"
      Abort "$(legacyUninstallError)"
    ${EndIf}
    Delete "$0\uninstall.exe"
    RMDir "$0"
  ${EndIf}
!macroend
