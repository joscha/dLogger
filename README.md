# DistributedLogger - a distributed logging system for Google Apps Script

When using [Google Apps Script](https://developers.google.com/apps-script/) with Script deployed as WebApps that are executed as the user accessing the WebApp, e.g.:

![image](https://raw.github.com/joscha/dLogger/gh-pages/images/WebApp_runAs_example.png)

you immediately run into the problem of not being able to access events logged by `Logger.log`, as those events go into the logging environment of executing user.

One way to work around this is sending exceptions via email, however the mail quotas of Google Apps Script only make this a feasible approach if you have a small number of users and definitely not for proper massive log output.

The other approach is to log into a spreadsheet shared to write to for anybody, e.g. `SpreadsheetApp.openById('XXX').addRow(…)` however the only problem with that is that for lots of log output, the [limits to spreadsheets imposed by Google](http://support.google.com/drive/bin/answer.py?hl=en&answer=2505921) are hit quite rapidly, meaning you constantly need to watch out for the limits and then clear your spreadsheet and/or use a new one.

If you don't, exceptions are thrown, possibly getting sent to your users via email. You don't want that.

This project helps you with this - it basically provides you with a simple log method paired with the ability to detect when a spreadsheet is close to hitting the limits and thus automatically rolling the current logs over to a newly created spreadsheet, seamlessly allowing you to produce virtually infinite log output into spreadsheets.

The use of spreadsheets has also one major advantage: if you open the spreadsheet where the events get logged to in your Google Docs account, you get a live impression of what's happening throughout your whole userbase.

## How does it work?
* DistributedLogger allows for multiple logging keys.
* Each key corresponds to one current (active) and zero to many old (full) spreadsheets.
  * For your project you can use one to many project keys. You also can use one DistributedLogger instance for multiple projects, using different keys.
* A trigger runs every X time units and checks whether the current spreadsheet is "full" (e.g. close to hitting the limit - the default threshold is 80%)
* If it is "full", then a new spreadsheet gets created and is used as the current target spreadsheet from then on.

## How to use
1. Get the contents of [lib/dLogger.js](https://raw.github.com/joscha/dLogger/master/lib/dLogger.js) and put them in a new GAS project.
2. Go to `Manage Versions` and save a new version
3. Go to `Project properties`, set the `Time zone` you want the log messages being dated in and copy the `Project key`.
4. Go to your project and add the copied `Project key` under `Resources -> Manage libraries`.
5. Have a look at the example below on how to use it or check out the [latest API Docs](https://script.google.com/macros/library/versions/d/MsqzXdC6h_VGFU8igz7L7qRjq1OGlSjhT).


For an easy start or just to check out how and if it works for you, you can use a predefined library run by me with the `Project key`:

> MsqzXdC6h_VGFU8igz7L7qRjq1OGlSjhT

Please note, that this is **NOT** the recommended way, because theoretically, with some effort, this would allow me or an attacker of my account to alter all the log data in the spreadsheets, so if you are concerned about your data, set up your own logger with the steps provided above. Only that way you have full governance with no risk.

## Example
```javascript
var KEY = 'myProject';

/**
* Run this to test - the old spreadsheets should be 80% filled and a second one created
* You might need to invoke this method multiple times from the script editor
* to hit the limits, as there is a maximum execution time and the spreadsheet limits aren't hit in that time.
*
* This would be the 
*/
function fill() {
  // Generate a huge log message
  var message = new Array(40).join("X").split("");
  
  // log that message to the DistributedLogger repeatedly
  for(var i = 0; i < 10000; i++) {
    // add a sequence number to the log message, so we can see no messages get lost
    message[0] = i;
    DistributedLogger.log(KEY, message);
  }
}

/**
* This needs to be run once, before using the .log method.
* It initializes the first spreadsheet and sets up a trigger.
* 
* Run this from the user account that is supposed to be the _receiver_ of the logs.
* 
* ATTENTION: DO NOT RUN THIS FROM AN END USER ACCOUNT!
*/
function setup() {
  // Initialize the spreadsheet
  DistributedLogger.setup(KEY);
  
  if(ScriptApp.getScriptTriggers().length === 0) {
    // There are no triggers, yet, so install trigger for keeping our spreadsheet alive.
    ScriptApp.newTrigger('keepAlive').timeBased().everyMinutes(1).create();
  }
}

/**
* This is the method being run in the trigger
*/                              
function keepAlive() {
  // This keeps our spreadsheets alive, e.g. replaces them with an empty one, once they come close to the limits.
  DistributedLogger.keepAlive();
}

/**
* This checks the quota of a specific key
*/
function checkQuota() {
  Logger.log(DistributedLogger.getQuota(KEY));
}
```

## Version history
_2013-01-14_ - **0.1**: Initial version

## Building from source
You can build via `cake build` or use `cake watch` for continuous builds during development.

## License
MIT License, see LICENSE.md
