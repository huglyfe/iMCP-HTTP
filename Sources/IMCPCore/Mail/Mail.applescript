-- Original adapter. Only fixed handlers are invoked; inputs arrive as Apple-event values.
on dispatch(operation, args)
  with timeout of 15 seconds
    considering case, diacriticals
      return my perform(operation, args)
    end considering
  end timeout
end dispatch
on selectedAccount(accountID)
  tell application id "com.apple.mail"
    set matches to every account whose id is accountID
    if (count matches) is not 1 then error number 9001
    return item 1 of matches
  end tell
end selectedAccount
on mailboxPath(box)
  tell application id "com.apple.mail"
    set parts to {name of box}
    set parentBox to container of box
    repeat while parentBox is not missing value

      if (count parts) >= 32 then error number 9003
      -- Mail reports a parent mailbox as class container; top-level containers may be accounts.
      if (class of parentBox) is not container and (class of parentBox) is not mailbox then exit repeat
      set beginning of parts to name of parentBox
      set parentBox to container of parentBox
    end repeat
    return parts
  end tell
end mailboxPath
on selectedMailbox(accountID, parts)
  set acct to my selectedAccount(accountID)
  set found to {}
  tell application id "com.apple.mail"
    repeat with box in mailboxes of acct

      if (my mailboxPath(contents of box)) is parts then set end of found to contents of box
    end repeat
  end tell
  if (count found) is 0 then error number 9001
  if (count found) is not 1 then error number 9004
  return item 1 of found
end selectedMailbox
on selectedMessage(box, itemID)
  set numericID to itemID as integer
  tell application id "com.apple.mail"
    set matches to messages of box whose id is numericID
    if (count matches) is 0 then error number 9001
    if (count matches) is not 1 then error number 9004
    return item 1 of matches
  end tell
end selectedMessage
on mailboxRecord(box)
  tell application id "com.apple.mail"
    return {my mailboxPath(box), unread count of box}
  end tell
end mailboxRecord
on textOrEmpty(value)
  if value is missing value then return ""
  return value as text
end textOrEmpty
on messageRecord(msg, bodyLimit)
  tell application id "com.apple.mail"
    set bodyText to ""
    set truncated to false
    if bodyLimit > 0 then
      set bodyText to my textOrEmpty(content of msg)
      if (count characters of bodyText) > bodyLimit then
        set bodyText to text 1 thru bodyLimit of bodyText
        set truncated to true
      end if
    end if
    set receivedDate to date received of msg
    if receivedDate is missing value then set receivedDate to ""
    return {(id of msg) as text, my textOrEmpty(subject of msg), my textOrEmpty(sender of msg), receivedDate, read status of msg, flagged status of msg, bodyText, truncated, bodyLimit > 0}
  end tell
end messageRecord
on perform(operation, args)
  tell application id "com.apple.mail"
    if operation is "accounts" then
      set output to {}
      repeat with acct in accounts

        if (count output) >= 200 then error number 9003
        set end of output to {id of acct, name of acct}
      end repeat
      return output
    end if
    set accountID to item 1 of args
    if operation is "mailboxes" then
      set acct to my selectedAccount(accountID)
      set skip to item 2 of args
      set pageSize to item 3 of args
      set boxes to mailboxes of acct
      set output to {}
      repeat with i from (skip + 1) to (count boxes)

        if (count output) is pageSize then return {output, true}
        set end of output to my mailboxRecord(item i of boxes)
      end repeat
      return {output, false}
    end if
    set parts to item 2 of args
    if operation is "createMailbox" then
      set newName to item 3 of args
      set acct to my selectedAccount(accountID)
      if (count parts) > 0 then my selectedMailbox(accountID, parts)
      set newParts to parts & {newName}
      repeat with component in newParts
        if contents of component contains "/" then error number 9007
      end repeat
      repeat with candidate in mailboxes of acct

        if (my mailboxPath(contents of candidate)) is newParts then error number 9004
      end repeat
      set AppleScript's text item delimiters to "/"
      set createPath to newParts as text
      set AppleScript's text item delimiters to ""
      make new mailbox at end of mailboxes of acct with properties {name:createPath}
      try
        return my mailboxRecord(my selectedMailbox(accountID, newParts))
      on error
        error number 9005
      end try
    end if
    set box to my selectedMailbox(accountID, parts)
    if operation is "renameMailbox" then
      set newName to item 3 of args
      set newParts to items 1 thru -1 of parts
      set item -1 of newParts to newName
      set acct to my selectedAccount(accountID)
      repeat with candidate in mailboxes of acct

        if (my mailboxPath(contents of candidate)) is newParts and newParts is not parts then error number 9004
      end repeat
      set name of box to newName
      try
        return my mailboxRecord(my selectedMailbox(accountID, newParts))
      on error
        error number 9005
      end try
    end if
    if operation is "fetch" then
      set searchText to item 3 of args
      set unreadOnly to item 4 of args
      set skip to item 5 of args
      set pageSize to item 6 of args
      set output to {}
      set matched to 0
      set totalCount to count messages of box
      repeat with i from 1 to totalCount

        set msg to message i of box
        set includeMessage to true
        if unreadOnly and (read status of msg) then set includeMessage to false
        if includeMessage and searchText is not "" then
          ignoring case, diacriticals
            set includeMessage to ((my textOrEmpty(subject of msg)) contains searchText) or ((my textOrEmpty(sender of msg)) contains searchText)
          end ignoring
        end if
        if includeMessage then
          if matched >= skip then
            if (count output) is pageSize then return {output, true}
            set end of output to my messageRecord(msg, 0)
          end if
          set matched to matched + 1
        end if
      end repeat
      return {output, false}
    end if
    set msg to my selectedMessage(box, item 3 of args)
    if operation is "get" then return my messageRecord(msg, item 4 of args)
    if operation is "edit" then
      try
        if item 4 of args is not "" then set read status of msg to ((item 4 of args) is "true")
        if item 5 of args is not "" then set flagged status of msg to ((item 5 of args) is "true")
        return my messageRecord(msg, 0)
      on error
        error number 9005
      end try
    end if
    if operation is "move" then
      set destination to my selectedMailbox(accountID, item 4 of args)
      move msg to destination
      -- Fail as uncertain if Mail changes its library ID, rather than matching another RFC Message-ID copy.
      try
        return my messageRecord(my selectedMessage(destination, item 3 of args), 0)
      on error
        error number 9005
      end try
    end if
    if operation is "delete" then
      delete msg
      return true
    end if
  end tell
  error number 9001
end perform
