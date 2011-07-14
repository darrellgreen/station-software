; Script generated by the HM NIS Edit Script Wizard.
;SetCompressor lzma

; HM NIS Edit Wizard helper defines
!define PRODUCT_NAME			"HiSPARC Client Application"
!define PRODUCT_VERSION			"${ADMIN_VERSION}.${USER_VERSION}"
!define PRODUCT_PUBLISHER		"Nikhef"
!define PRODUCT_WEB_SITE		"http://www.hisparc.nl"
!define PRODUCT_KEY				"Software\${PRODUCT_NAME}"
!define PRODUCT_UNINST_KEY		"Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
!define PRODUCT_UNINST_ROOT_KEY	"HKLM"

#!addincludedir "nsisinstaller"

!include interface2.nsh

#
# pagina's voor de installer (nu opgenomen in interface2.nsh)
#
;Page directory
;Page custom userinput1 "" ": Instellingen"
;Page custom userinput2 "" ": Lokale Database Instellingen"
;Page custom userinput3 "" ": Sensoren"
;Page custom startinstall "" ": Klaar voor installatie"
;Page instfiles

#
# pagina's voor de uninstaller (nu opgenomen in interface2.nsh)
#
;UninstPage uninstConfirm
;UninstPage instfiles

!include variables.nsh

#
# User input parsing
#
!include userinput.nsh

Name		"${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile		"..\..\releases\hisparcInstaller_v${PRODUCT_VERSION}.exe"
InstallDir	"$PROGRAMFILES\HiSPARC Client Application"

ShowInstDetails hide
ShowUnInstDetails hide

Function .onInit
  InitPluginsDir
  
  CreateDirectory "$INSTDIR\hisparc"
  
  SetOutPath $PLUGINSDIR
  File /r *.ini
  
  !insertmacro MUI_LANGDLL_DISPLAY
  # check windows versie
  xtInfoPlugin::IsWindowsME
  Pop $0
  xtInfoPlugin::IsWindows98
  Pop $1
  xtInfoPlugin::IsWindows95
  Pop $2

  ${If} $0 == "true"
  ${OrIf} $1 == "true"
  ${OrIf} $2 == "true"
     MessageBox MB_ICONEXCLAMATION "The PC runs an obsolete Windows version.$\nHiSPARC requires Windows XP or 7.$\nThe installation terminates."
     Quit
  ${EndIf}

  # check if user has administrator rights.
  xtInfoPlugin::IsAdministrator
  Pop $0

  ${If} $0 == "false"
     MessageBox MB_ICONEXCLAMATION "You have no administrator rights.$\nThe installation terminates."
     Quit
  ${EndIf}
FunctionEnd

#
# Copy files to the directory on the harddisk
#
Section -CopyFilesForInstall
  SetOutPath "$INSTDIR\hisparc\"
  SetOverwrite on
  File /r /x .svn ..\..\..\persistent

  SetOutPath "$INSTDIR\hisparc\persistent\downloads\"
  SetOverwrite on
  File /r "..\..\releases\adminUpdater_v${ADMIN_VERSION}.exe" "..\..\releases\userUnpacker_v${USER_VERSION}.exe"
  
  #Create directory for the admin, user and main installer to put their uninstallers!
  CreateDirectory "$INSTDIR\hisparc\persistent\uninstallers"
SectionEnd

#
# Pre installation phase (e.g. user input)
#
#Section -PreInstallation
  !include preinstallation.nsh
#SectionEnd

Section -WriteRegKeys
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_KEY}" "Path"		"$INSTDIR"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_KEY}" "DisplayName" "${PRODUCT_NAME}"
SectionEnd

Section -AdminInstallation
  ExecWait '$INSTDIR\hisparc\persistent\downloads\adminUpdater_v${ADMIN_VERSION}.exe /S'
SectionEnd

Section -UserInstallation
  ExecWait '$INSTDIR\hisparc\persistent\downloads\userUnpacker_v${USER_VERSION}.exe /S'
SectionEnd

#
# Post installation section, e.g. user account creation
#Section -PostInstallation
  !include postinstallation.nsh
#SectionEnd

Section -AdditionalIcons
  SetOutPath $INSTDIR
  SetShellVarContext all
  CreateDirectory "$SMPROGRAMS\HiSPARC"
  CreateShortCut  "$SMPROGRAMS\HiSPARC\StartHiSPARCSoftware.lnk" "$INSTDIR\hisparc\persistent\startstopbatch\StartUserMode.bat"
  CreateShortCut  "$SMPROGRAMS\HiSPARC\LocalDiagnosticTool.lnk"  "$INSTDIR\hisparc\user\diagnostictool\run_diagnostictool.bat"
  CreateShortCut  "$SMPROGRAMS\HiSPARC\HiSPARCDAQ.lnk"           "$INSTDIR\hisparc\user\hisparcdaq\run_hisparcdaq.bat"
  CreateShortCut  "$SMPROGRAMS\HiSPARC\DSPMon.lnk"               "$INSTDIR\hisparc\user\dspmon\DSPMon.exe"
  CreateShortCut  "$SMPROGRAMS\HiSPARC\Uninstall.lnk"            "$INSTDIR\hisparc\persistent\uninstallers\mainuninst.exe" 
  #Add shortcuts to the startup folder
  CreateShortCut "$SMSTARTUP\StartHiSPARCSoftware.lnk"           "$INSTDIR\hisparc\persistent\startstopbatch\StartUp.bat"
SectionEnd

Section -Post
  WriteUninstaller "$selectedDrive:\persistent\uninstallers\mainuninst.exe"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayName"     "$(^Name)"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\hisparc\persistent\uninstallers\mainuninst.exe"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayVersion"  "${PRODUCT_VERSION}"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "URLInfoAbout"    "${PRODUCT_WEB_SITE}"
  WriteRegStr ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "Publisher"       "${PRODUCT_PUBLISHER}"
SectionEnd

#Section -UninstallAllSoftware
  !include uninstaller.nsh
#SectionEnd

Section -Reboot
  Delete '$INSTDIR\hisparc\persistent\downloads\adminUpdater.exe'
  Delete '$INSTDIR\hisparc\persistent\downloads\userunpacker.exe'
  
  AccessControl::GrantOnFile "$INSTDIR" "(BU)" "FullAccess"

  MessageBox MB_YESNO|MB_ICONQUESTION "Do you want to restart the PC?$\n\
  On reboot Windows automatically activates the hisparc user account and DAQ." IDYES Reboot IDNO NoReboot
  
  Reboot:
     ExecWait "shutdown -r -f -t 0"
  NoReboot:
SectionEnd