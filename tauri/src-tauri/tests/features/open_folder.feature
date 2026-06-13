Feature: Opening a project folder in the OS file manager

  The project row's Open Folder button reveals a project in the OS file
  manager (Explorer on Windows). Before handing off to the platform layer,
  the command guards against a path that has been moved or deleted since the
  list was rendered, so the user gets a clear message instead of an empty
  file-manager window.

  Scenario: opening a folder that no longer exists reports an error
    When I try to open a project folder that does not exist
    Then opening the folder fails because it is missing
