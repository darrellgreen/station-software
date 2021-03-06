#
#   uninstaller.nsh ------
#   Create the admin uninstaller.
#   Aug 2013: some applications still use the 32-bit registry
#

Function un.onInit
  DetailPrint "admin-un.onInit"
  
  InitPluginsDir
  # check if user has administrator rights
  xtInfoPlugin::IsAdministrator
  Pop $0
  ${If} $0 == "false"
    MessageBox MB_ICONEXCLAMATION "You have no administrator rights!$\nAdmin-Uninstallation aborted."
    Quit
  ${EndIf}
  
  # Check for 32-bit or 64-bit computer
  System::Call "kernel32::GetCurrentProcess() i .s"
  System::Call "kernel32::IsWow64Process(i s, *i .r0)"
  StrCmp $0 "0" is32 is64
is32:
  SetRegView 32
  StrCpy $Architecture "32"
  Goto proCeed
is64:
  SetRegView 64
  StrCpy $Architecture "64"
  
proCeed:
  ReadRegStr $HisparcDir HKLM "${HISPARC_KEY}" ${REG_PATH}
  StrCmp $HisparcDir "" noReg
  StrCpy $AdminDir   "$HisparcDir\admin"
  ${DirState} $AdminDir $Result
  ${If} $Result < 0
    MessageBox MB_ICONEXCLAMATION "FATAL: Folder $AdminDir does not exist!$\nAdmin-Uninstallation aborted."
    Quit
  ${Endif}
  DetailPrint "AdminDir: $AdminDir"
  
  ${If} $Architecture == "32"
    StrCpy $OpenVpnDir "$AdminDir\openvpn32"
    StrCpy $TvncFolder "$AdminDir\tightvnc32"
  ${Else}
    StrCpy $OpenVpnDir "$AdminDir\openvpn64"
    StrCpy $TvncFolder "$AdminDir\tightvnc64"
  ${Endif}
  DetailPrint "OpenVpnDir: $OpenVpnDir"
  DetailPrint "TvncFolder: $TvncFolder"
  Return
  
noReg:
  MessageBox MB_ICONEXCLAMATION "FATAL: Registry entry ${REG_PATH} not set or defined!$\nAdmin-Uninstallation aborted."
  Quit
FunctionEnd

#
# Remove OpenVPN
#
Section un.UninstOpenVPN
  DetailPrint "admin-un.UninstOpenVPN"
  # OpenVPN 2.2.2 64-bit version, still reads its registry as a 32-bit application
  SetRegView 32
  # remove service
  ExecWait '"$OpenVpnDir\bin\openvpnserv.exe" -remove' $Result
  DetailPrint "VPN openvpnserv: $Result"
  # delete reg keys
  DeleteRegKey HKLM ${OPENVPN_KEY}
  # remove the tap devices
  ExecWait '"$OpenVpnDir\bin\tapinstall.exe" remove tap0901' $Result
  DetailPrint "VPN tapremove: $Result"
  # remove the folder
  RMDir /r /REBOOTOK "$AdminDir\openvpn32"
  RMDir /r /REBOOTOK "$AdminDir\openvpn64"
  ${If} $Architecture == "64"
    SetRegView 64
  ${Endif}
SectionEnd

#
# Remove TightVNC.
#
Section un.UninstTightVNC
  DetailPrint "admin-un.UninstTightVNC"
  # remove service
  StrCpy $Program "$TvncFolder\${VNC_SERVICENAME}.exe"
  ExecWait '"$Program" -remove -silent' $Result
  DetailPrint "VNC tightvnc: $Result"
  # delete reg keys
  DeleteRegKey HKLM ${TIGHTVNCKEY}   
  # remove the folder
  RMDir /r /REBOOTOK "$AdminDir\tightvnc32"
  RMDir /r /REBOOTOK "$AdminDir\tightvnc64"
SectionEnd

#
# Remove nscp (NAGIOS)
#
Section un.UninstNscp
  DetailPrint "admin-un.UninstNscp"
  ExecWait '"$AdminDir\nsclientpp\NSClient++.exe" /stop' $Result
  DetailPrint "Nagios stop: $Result"
  ExecWait '"$AdminDir\nsclientpp\NSClient++.exe" /uninstall' $Result
  DetailPrint "Nagios uninstall: $Result"
  RMDir /r /REBOOTOK "$AdminDir\nsclientpp"
SectionEnd

#
# Remove ODBC
#
Section un.UninstODBC
  DetailPrint "admin-un.UninstODBC"
  SetRegView 32
  DeleteRegKey   HKLM ${ODBCREGKEY}
  DeleteRegValue HKLM "${ODBCDSREGKEY}" "buffer"
  ExecWait '"$AdminDir\odbcconnector\Uninstall_HiSPARC.bat"' $Result
  DetailPrint "ODBC uninstall: $Result"
  RMDir /r /REBOOTOK "$AdminDir\odbcconnector"
  ${If} $Architecture == "64"
    SetRegView 64
  ${Endif}
SectionEnd

#
# Remove National Instruments Runtime Engine.
#
Section un.UninstNIRuntime
  DetailPrint "admin-un.UninstNIRuntime"
  SetRegView 32
  MessageBox MB_YESNO|MB_ICONQUESTION "Do you also want to remove the NI Runtime Engine?" IDYES removeNI IDNO keepNI
removeNI:
  ReadRegStr $NIdir HKLM "${LABVIEW_KEY}" ${LABVIEW_DIR}
  ExecWait '"$NIdir\Shared\NIUninstaller\uninst.exe" /qb /x all' $Result
  DetailPrint "LabVIEW uninst: $Result"
  RMDir /r /REBOOTOK "$NIdir"
keepNI:
  ${If} $Architecture == "64"
    SetRegView 64
  ${Endif}
SectionEnd

#
# Remove the entire admin folder.
#
Section un.UninstProgs
  DetailPrint "admin-un.UninstProgs"
  # remove the entire admin folder
  RMDir /r /REBOOTOK "$AdminDir"
SectionEnd

#
# Stop and remove services from the service list.
#
Section un.UninstallServices
  DetailPrint "admin-un.UninstallServices"
  # stop the services
  SimpleSC::StopService ${VPN_SERVICENAME}
  SimpleSC::StopService ${VNC_SERVICENAME}
  SimpleSC::StopService ${NSCP_SERVICENAME}
  # remove the services
  SimpleSC::RemoveService ${VPN_SERVICENAME}
  SimpleSC::RemoveService ${VNC_SERVICENAME}
  SimpleSC::RemoveService ${NSCP_SERVICENAME}
SectionEnd

Section un.Uninstall
  DetailPrint "admin-un.Uninstall"
  Delete "$HisparcDir\persistent\uninstallers\adminuninst.exe"
  SetAutoClose true
SectionEnd
