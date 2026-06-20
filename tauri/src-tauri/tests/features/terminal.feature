Feature: External terminal launch command line

  Sessions launched from a project open in the user's chosen shell
  (Command Prompt or PowerShell) and either a brand-new window or a tab in
  the app's dedicated Windows Terminal window. The argument builders are
  pure so this behaviour is verified on every host, not just Windows.

  Scenario: a Command Prompt session keeps the shell open with /K
    When I build the shell invocation for "cmd" running "claude"
    Then the shell invocation is "cmd /K claude"

  Scenario: a Windows PowerShell session keeps the shell open with -NoExit
    When I build the shell invocation for "powershell" running "claude"
    Then the shell invocation is "powershell.exe -NoExit -Command claude"

  Scenario: a PowerShell 7 session targets the pwsh binary
    When I build the shell invocation for "pwsh" running "claude"
    Then the shell invocation is "pwsh.exe -NoExit -Command claude"

  Scenario: a new tab targets the app's Windows Terminal window
    When I build the Windows Terminal args for placement "newTab" shell "cmd" running "claude" in "C:\proj"
    Then the Windows Terminal args are "-w bmad-manager new-tab -d C:\proj cmd /K claude"

  Scenario: a new window forces a fresh Windows Terminal window
    When I build the Windows Terminal args for placement "newWindow" shell "powershell" running "claude" in "C:\proj"
    Then the Windows Terminal args are "-w new new-tab -d C:\proj powershell.exe -NoExit -Command claude"

  Scenario: the standalone fallback wraps the shell in a detached start
    When I build the fallback args for shell "powershell" running "pi"
    Then the fallback args are "/C start  powershell.exe -NoExit -Command pi"
