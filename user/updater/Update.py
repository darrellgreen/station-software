import ConfigParser
import sched
import time
import random
import os
import sys

sys.path.append("../pythonshared")

import checkFiles
from Checker import Checker
from hslog import log, setLogMode, MODE_BOTH, SEVERITY_CRITICAL

CONFIG_INI = "config.ini"
PERSISTENT_INI = "../../persistent/configuration/config.ini"
ADMINUPDATE_NAME = "adminUpdater"


class Updater:
    config = ConfigParser.ConfigParser()
    timeBetweenChecks = 0  # (in seconds)
    # Start time of the interval in which checks may be performed on a
    # day (in seconds) e.g. 0 is midnight, 7200 is 2am
    timeStartCheckInterval = 0
    # End time of the interval in which checks may be performed on a
    # day (in seconds) e.g. 0 is midnight, 7200 is 2am
    timeStopCheckInterval = 0
    checkerInitialDelay = 0  # Bool with if there is an initial delay
    scheduler = sched.scheduler(time.time, time.sleep)
    checker = Checker()

    # Check if there is already an update to install in admin mode and if the
    # user is in admin mode
    def checkIfUpdateToInstall(self):
        isAdmin = checkFiles.checkIfAdmin()
        currentAdmin = self.config.get("Version", "CurrentAdmin")
        currentUser = self.config.get("Version", "CurrentUser")

        print "You are Administrator: ", isAdmin
        print "Current Admin Version: ", currentAdmin
        print "Current User Version:  ", currentUser

        if isAdmin:
            location = "../../persistent/downloads"
            found, fileFound = checkFiles.checkIfNewerFileExists(location,
                ADMINUPDATE_NAME, int(currentAdmin))
            #print "found is %s" % found
            if found:
                os.system(".\\runAdminUpdate.bat "
                          "../../persistent/downloads/%s" % fileFound)

    def calculateInitialDelay(self):
        if self.checkerInitialDelay == 1:
            #Calculate the time now
            #..and the time it is be today at four and at noon
            now = int(time.time())
            last_midnight = now - (now % 86400)
            today_at_starttime = last_midnight + self.timeStartCheckInterval
            today_at_stoptime = last_midnight + self.timeStopCheckInterval

            #Check if you are allowed to update already
            #(in the interval between starttime and stoptime)
            if today_at_starttime < now < today_at_stoptime:
                today_random_moment = random.randint(now, today_at_stoptime)
                return today_random_moment - now
            else:
                tomorrow_at_four = today_at_starttime + 86400
                tomorrow_at_noon = today_at_stoptime + 86400
                tomorrow_random_moment = random.randint(tomorrow_at_four,
                                                        tomorrow_at_noon)
                return tomorrow_random_moment - now
        else:
            return 0

    def performOneUpdateCheck(self):
        delay = self.calculateInitialDelay()
        self.scheduler.enter(delay, 1, self.checker.checkForUpdates, '')
        self.scheduler.run()

    def performContinuousCheck(self):
        while True:
            self.scheduler.enter(self.timeBetweenChecks, 1,
                                 self.checker.checkForUpdates, '')
            self.scheduler.run()

    def __init__(self):
        self.config.read([CONFIG_INI, PERSISTENT_INI])
        self.timeBetweenChecks = int(self.config.get('Update',
                                     'IntervalBetweenChecks'))
        self.timeStartCheckInterval = int(self.config.get('Update',
                                          'CheckerIntervalStartTime'))
        self.timeStopCheckInterval = int(self.config.get('Update',
                                         'CheckerIntervalStopTime'))
        self.checkerInitialDelay = int(self.config.get('Update',
                                       'CheckerInitialDelay'))

try:
    setLogMode(MODE_BOTH)
    updater = Updater()
    updater.checkIfUpdateToInstall()
    updater.performOneUpdateCheck()
    updater.performContinuousCheck()
except KeyboardInterrupt:
    exit
except:
    log("Updating failed due to %s, restart the checker!" %
        str(sys.exc_info()[1]), severity=SEVERITY_CRITICAL)
    exit
