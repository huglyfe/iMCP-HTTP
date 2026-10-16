-- Original adapter using only Notes' public scripting dictionary.
on dispatch(operation, args)
  with timeout of 15 seconds
    considering case, diacriticals
      return my perform(operation, args)
    end considering
  end timeout
end dispatch
on selectedFolder(folderID)
  tell application id "com.apple.Notes"
    set matches to folders whose id is folderID
    if (count matches) is not 1 then error number 9001
    return item 1 of matches
  end tell
end selectedFolder
-- Resolve the note and its folder together. Shared notes can return an unusable
-- container reference, even though folder-scoped access succeeds.
on locateNote(noteID)
  tell application id "com.apple.Notes"
    set location to missing value
    repeat with candidate in folders
      set matches to notes of candidate whose id is noteID
      if (count matches) > 1 then error number 9004
      if (count matches) is 1 then
        if location is not missing value then error number 9004
        set location to {item 1 of matches, contents of candidate}
      end if
    end repeat
    if location is missing value then error number 9001
    return location
  end tell
end locateNote
on accountOfFolder(target)
  tell application id "com.apple.Notes"
    repeat 32 times
      set target to container of target
      if class of target is account then return id of target
    end repeat
  end tell
  error number 9003
end accountOfFolder
on editableNote(target)
  tell application id "com.apple.Notes"
    if password protected of target then error number 9002
    if (count attachments of target) > 0 then error number 9002
  end tell
end editableNote
on noteRecord(target, folderID, bodyLimit)
  tell application id "com.apple.Notes"
    set html to ""
    set plainTextValue to ""
    set truncated to false
    set includeBody to bodyLimit > 0 and not (password protected of target)
    if includeBody then
      set html to body of target
      set plainTextValue to plaintext of target
      if (count characters of html) > bodyLimit then
        set html to text 1 thru bodyLimit of html
        set truncated to true
      end if
      if (count characters of plainTextValue) > bodyLimit then
        set plainTextValue to text 1 thru bodyLimit of plainTextValue
        set truncated to true
      end if
    end if
    return {id of target, folderID, name of target, modification date of target, password protected of target, shared of target, html, plainTextValue, truncated, includeBody}
  end tell
end noteRecord
on savedNote(target, folderID)
  try
    return my noteRecord(target, folderID, 65536)
  on error
    -- A write already succeeded; a readback failure must not invite a blind retry.
    error number 9005
  end try
end savedNote
on appendHTML(existing, addition)
  set characterCount to count characters of existing
  if characterCount >= 7 then
    ignoring case
      repeat with indexValue from 1 to (characterCount - 6)
        if (text indexValue thru (indexValue + 6) of existing) is "</body>" then
          set prefixText to ""
          if indexValue > 1 then set prefixText to text 1 thru (indexValue - 1) of existing
          return prefixText & addition & (text indexValue thru -1 of existing)
        end if
      end repeat
    end ignoring
  end if
  return existing & addition
end appendHTML
on perform(operation, args)
  tell application id "com.apple.Notes"
    if operation is "accounts" then
      set output to {}
      repeat with acct in accounts
        if (count output) >= 200 then error number 9003
        set end of output to {id of acct, name of acct}
      end repeat
      return output
    end if
    if operation is "folders" then
      set accountID to item 1 of args
      set matches to accounts whose id is accountID
      if (count matches) is not 1 then error number 9001
      set skip to item 2 of args
      set pageSize to item 3 of args
      set output to {}
      set matched to 0
      -- App-level folders include nested folders; account ownership is checked through container IDs.
      repeat with candidate in folders
        if (my accountOfFolder(contents of candidate)) is accountID then
          if matched >= skip then
            if (count output) is pageSize then return {output, true}
            set end of output to {id of candidate, name of candidate, id of container of candidate, shared of candidate}
          end if
          set matched to matched + 1
        end if
      end repeat
      return {output, false}
    end if
    if operation is "fetch" then
      set targetFolder to my selectedFolder(item 1 of args)
      set searchText to item 2 of args
      set skip to item 3 of args
      set pageSize to item 4 of args
      set output to {}
      set matched to 0
      set totalCount to count notes of targetFolder
      repeat with i from 1 to totalCount
        set target to note i of targetFolder
        set includeNote to true
        if searchText is not "" then
          ignoring case, diacriticals
            set includeNote to name of target contains searchText
            if not includeNote and not (password protected of target) then set includeNote to plaintext of target contains searchText
          end ignoring
        end if
        if includeNote then
          if matched >= skip then
            if (count output) is pageSize then return {output, true}
            set end of output to my noteRecord(target, id of targetFolder, 0)
          end if
          set matched to matched + 1
        end if
      end repeat
      return {output, false}
    end if
    if operation is "create" then
      set targetFolder to my selectedFolder(item 1 of args)
      set created to make new note at targetFolder with properties {body:item 2 of args}
      return my savedNote(created, id of targetFolder)
    end if
    set location to my locateNote(item 1 of args)
    set target to item 1 of location
    set targetFolder to item 2 of location
    if operation is "get" then return my noteRecord(target, id of targetFolder, item 2 of args)
    if operation is "delete" then
      delete target
      return true
    end if
    if operation is "move" then
      set destination to my selectedFolder(item 2 of args)
      if (my accountOfFolder(targetFolder)) is not (my accountOfFolder(destination)) then error number 9006
      move target to destination
      try
        set moved to my locateNote(item 1 of args)
        if (id of item 2 of moved) is not (id of destination) then error number 9005
        return my noteRecord(item 1 of moved, id of destination, 65536)
      on error
        error number 9005
      end try
    end if
    my editableNote(target)
    if operation is "edit" then
      set body of target to item 2 of args
      return my savedNote(target, id of targetFolder)
    end if
    if operation is "append" then
      set existing to body of target
      if (count characters of existing) > 65536 then error number 9003
      set body of target to my appendHTML(existing, item 2 of args)
      return my savedNote(target, id of targetFolder)
    end if
  end tell
  error number 9001
end perform
