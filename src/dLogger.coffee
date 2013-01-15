l = null

(->
  class DistributedLogger

    @CELL_LIMIT: 4e5
    @EXCEED_PERCENTAGE: 0.8

    getDb_: ->
      ScriptDb.getMyDb()

    getEmail_: ->
      Session.getActiveUser().getEmail()

    log: (key, m, sheetName = null) ->
      spreadsheet = null
      now = new Date()
      try
        throw "log: Parameter 'key' is not optional" unless key

        spreadsheet = @getCurrentSpreadsheet key
        
        throw "log: spreadsheet wasn't available - did you run 'setup' at least once?" unless spreadsheet

        if sheetName
          sheet = spreadsheet.getSheetByName sheetName
          sheet = spreadsheet.insertSheet sheetName unless sheet
        else
          sheet = spreadsheet.getSheets()[0]

        if m instanceof Array
          message = m[..]
          message.unshift now
        else
          message = [now, m]

        sheet.appendRow message
        return
      catch e
        Logger.log e
        try
          if MailApp.getRemainingDailyQuota() > 0
            body =  """
                    On #{now}, adding log entries to the spreadsheet: https://docs.google.com/spreadsheet/ccc?key=#{s.getId()} failed because of:
                    #{e.toString()}
                    -- 
                    This email was sent by a user - please do not reply directly!
                    """
            MailApp.sendEmail spreadsheet.getOwner(), "GAS: DistributedLogger: Error in '#{key}'", body, noReply: true
            return
        catch e
          ### we can't do anything about it - if we don't catch this, the user gets an email - we don't want that ###
          Logger.log e
          return

    getCurrentSpreadsheet: (key) ->
      db = @getDb_()

      result = db.query
        key:    key

      result = result.sortBy 'created', db.DESCENDING

      return null unless result.hasNext()
      SpreadsheetApp.openById result.next().spreadsheet

    createSpreadsheet: (key) ->
      now = new Date()
      ob = 
        key: key
        created: now.getTime()

      s = SpreadsheetApp.create "GAS: DistributedLogger: #{key} (created #{now.toUTCString()})"
      s.setAnonymousAccess false, true
      ob.spreadsheet = s.getId()

      @getDb_().save ob
      s

    isExceeded: (spreadsheet, percentage) ->
      total = 0
      for sheet in spreadsheet.getSheets()
        r = sheet.getDataRange()
        total += r.getNumRows() * r.getNumColumns()
        currentQuota =  total / DistributedLogger.CELL_LIMIT
        if currentQuota >= (percentage ? 1)
          Logger.log "We used up #{Number(currentQuota * 100).toPrecision 3}% of all cells"
          return true
      Logger.log "We only used up #{Number(currentQuota * 100).toPrecision 3}% of all cells so far"
      return false

    getQuota: (key) ->
      throw "Parameter 'key' is not optional" unless key
      spreadsheet = @getCurrentSpreadsheet key
      throw "A spreadsheet for key '#{key}' does not exist - did you run setup(key)?" unless spreadsheet
      total = 0
      for sheet in spreadsheet.getSheets()
        r = sheet.getDataRange()
        total += r.getNumRows() * r.getNumColumns()
      total / DistributedLogger.CELL_LIMIT

    checkQuota: (key = null, percentage = DistributedLogger.EXCEED_PERCENTAGE) ->
      lock = LockService.getPrivateLock()
      if lock.tryLock 0
        try
          if key
            keys = [key]
          else
            result = @getDb_().query({})
            obj = {}
            while result.hasNext()
              obj[result.next().key] = true
            keys = []
            for key,v of obj
              keys.push key

          for key in keys
            try
              s = @getCurrentSpreadsheet key
              create = not s or @isExceeded s, percentage
            catch e
              # In case it was deleted for example
              create = true

            if create
              s = @createSpreadsheet key
              if MailApp.getRemainingDailyQuota() > 0
                body =  """
                        A new spreadsheet for your distributed logging key '#{key}' has been created.
                        You can find it here: https://docs.google.com/spreadsheet/ccc?key=#{s.getId()}
                        """
                MailApp.sendEmail @getEmail_(), "GAS: DistributedLogger: '#{key}' renewed", body, noReply: true
              return
        catch e
          Logger.log e
          return
        finally
          lock.releaseLock()

  l = new DistributedLogger
  return
)()

`
/**
* This keeps the logging spreadsheets alive.
* E.g. creates a new one after hitting X% of the 400,000 cell limit (see here http://support.google.com/drive/bin/answer.py?hl=en&answer=2505921).
*
*
* ***ATTENTION: DO NOT RUN THIS FROM AN END USER ACCOUNT, IT WILL CREATE SPREADSHEETS IN HIS/HER ACCOUNT YOU CAN'T ACCESS***
*
*
* This should be run in a trigger by the receiver of the logs (*not* by the user of the library)
* E.g. if you (lets say adam@host.com) are the developer of the script and want to receive the logs, you should run this in a trigger - whereas one or many of your clients would only use the log method.
*
* How often you will need to run this trigger depends on how much log data is written - rule of thumb is:
* frequencyInMinutes = (users*messagesPerMinute*(messageSize+1)) / 400,000
* Meaning for 10000 users logging ten messages per minute with a size of 3 fields (e.g. an array of length 3) you'd need a trigger running keepAlive every minute.
*
* @param {String} key (Optional) The spreadsheet key to keep alive - if omitted all spreadsheets of the invoking user are kept alive (e.g. renewed)
* @param {number} percentage (Optional, defaults to 0.8) The percentage of the maximum limit (currently 400,000 cells) when to renew a spreadsheet.
*/
function keepAlive(key, percentage) {
  l.checkQuota.apply(l, arguments);
};

/**
* This initializes a new spreadsheet to log to under a given key
*
* ***ATTENTION: DO NOT RUN THIS FROM AN END USER ACCOUNT, IT WILL CREATE SPREADSHEETS IN HIS/HER ACCOUNT YOU CAN'T ACCESS***
*
* @param {String} key The spreadsheet key to prepare for logging.
*/
function setup(key) {
  l.checkQuota(key);
}

/**
* Returns the quota (percentage)
*
* @param {String} key The spreadsheet key to check the quota for.
* @return {number} The percentage between 0.0 and 1.0
*/
function getQuota(key) {
  return l.getQuota(key);
}

/**
* This is the method that does the actual logging.
* Use this from your end user scripts.
* Make sure that each key you use is properly initialized, e.g. setup(key) has been run for it once.
*
* @param {String} key The key of the spreadsheet to log to.
* @param {Object} message The message to log to the spreadsheet. Can be of any type. If it is an array, each field corresponds to one spreadsheet cell. If an array, the maximum size is about 50 (longer arrays have been found to be skipped sometimes). If you are concerned about easily hitting the spreadsheet cell limit, keep the length of the array as small as possible.
* @param {String} sheetName (Optional) a sheet name to log to. Will be inserted as a new spreadsheet if not existent. If omitted, the message will be logged to the first sheet. Be aware that a spreadsheet may not have more than 200 different sheets - see http://support.google.com/drive/bin/answer.py?hl=en&answer=2505921.
*/
function log(key, message, sheetName) {
  l.log.apply(l, arguments);
}`