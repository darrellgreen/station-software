from time import sleep, time
from cPickle import dumps
from urllib import urlencode
from urllib2 import urlopen, HTTPError, URLError
import socket
from threading import Thread, Semaphore, Event

from Observer import Observer
from StorageManager import StorageManager
from hslog import log
from NagiosPush import NagiosPush
from NagiosResult import NagiosResult
from UserExceptions import ThreadCrashError

# TODO add observer
# use BUI's trick to stop a thread
BATCHSIZE = 100
MINWAIT = 1  # minimum time to wait in seconds after a failed attempt
             # the waiting time will be doubled for each failed attempt
MAXWAIT = 60  # maximum time to wait in seconds after a failed attempt

# To make sure there is no timeout set at socket level
socket.setdefaulttimeout(None)

# Python >= 2.5 has hashlib
try:
    from hashlib import md5
    def md5_sum(s):
        return md5(s).hexdigest()
except:
    print "ERROR: No hashlib found. Using md5 instead."
    import md5
    def md5_sum(s):
        return md5.new(s).hexdigest()


class Uploader(Observer, Thread):
    def __init__(self, serverID, stationID, password, URL, config,
                 retryAfter=MINWAIT, maxWait=MAXWAIT,
                 minBatchSize=BATCHSIZE, maxBatchSize=BATCHSIZE):
        self.storageManager = StorageManager()
        self.serverID = serverID
        self.stationID = stationID
        self.password = password
        self.URL = URL
        self.nagiosPush = NagiosPush(config)
        self.minBatchSize = minBatchSize
        self.maxBatchSize = maxBatchSize
        self.retryAfter = MINWAIT
        self.maxWait = MAXWAIT

        # lock to protect numEvents
        self.numEventsLock = Semaphore(1)

        # Semaphore to block if the number of events drops below minBatchSize
        self.noEventsSem = Semaphore(0)

        Thread.__init__(self)
        self.stop_event = Event()
        self.isRunning = False

    def setNumServer(self, numServer):
        """Sets the number of servers to upload to.

        Need to be set before changing the UploadedTo-status
        of events in the StorageManager.

        """
        self.storageManager.setNumServer(numServer)

    def stop(self):
        self.stop_event.set()
        # release semaphore
        self.noEventsSem.release()

    crashes = []

    def init_restart(self):
        """Support for restarting crashed threads."""

        if len(self.crashes) > 3 and time() - self.crashes[-3] < 60.:
            raise ThreadCrashError("Thread has crashed three times in "
                                   "less than a minute")
        else:
            # FIXME correctly work out that super stuff.  I think that
            # the superclasses should both use super, but ...?
            #super(Uploader, self).__init__()
            Thread.__init__(self)
            self.crashes.append(time())

    def notify(self, count=1):
        """Notify the uploader that count events were received."""

        if (self.isRunning):
            shouldRelease = 0
            self.numEventsLock.acquire()

            oldNumEvents = self.numEvents
            self.numEvents += count
            log("Uploader %i: %i events pending." %
                (self.serverID, self.numEvents))

            # calculate if uploader-thread should be unblocked
            if (self.numEvents >= self.minBatchSize and
                oldNumEvents < self.minBatchSize):
                shouldRelease = 1

            self.numEventsLock.release()

            if (shouldRelease):
                self.noEventsSem.release()

    def __getNumEventsToUpload(self):
        """Gives the number of events that the Uploader can upload now.

        The result will be between min and max batch size. If insufficient
        events are available this function will block on noEventSem.

        """

        shouldBlock = False
        self.numEventsLock.acquire()
        res = min(self.numEvents, self.maxBatchSize)
        if (res < self.minBatchSize):
            shouldBlock = True
        self.numEventsLock.release()

        if shouldBlock:
            log("Uploader %i: Blocked: Too few events" % self.serverID)
            self.noEventsSem.acquire()
            log("Uploader %i: Unblocked" % self.serverID)
            return self.minBatchSize
        else:
            return res

    def __upload(self, elist):
        """Upload a list of events to the database server."""

        data = dumps(elist)
        checksum = md5_sum(data)

        params = urlencode({'station_id': self.stationID,
                            'password': self.password,
                            'data': data,
                            'checksum': checksum})

        # Open the connection and send our data. Exceptions are caught
        # explicitly to make sure we understand the implications of errors.
        try:
            f = urlopen(self.URL, params)
        except (URLError, HTTPError), msg:
            # For example: connection refused or internal server error
            returncode = str(msg)
        except Exception, msg:
            returncode = ('Uncatched exception occured in function '
                          '__upload: %s' % str(msg))
        else:
            returncode = f.read()

        return returncode

    def run(self):
        log("Uploader %i: Thread started for %s." % (self.serverID, self.URL),
            severity=2)

        # Initialize storage manager
        self.storageManager.openConnection()

        # Number of events that have been received
        log("Uploader %i: Getting number of events to upload." % self.serverID)
        self.numEvents = self.storageManager.getNumEventsServer(self.serverID)
        log("Uploader %i: %i events in storage." %
            (self.serverID, self.numEvents))

        self.isRunning = True

        numFailedAttempts = 0
        while not self.stop_event.isSet():
            bsize = self.__getNumEventsToUpload()

            (elist, eidlist) = self.storageManager.getEvents(self.serverID,
                                                             bsize)
            returncode = self.__upload(elist)
            if returncode == '100':
                log("Uploader %i: %d events uploaded to %s." %
                    (self.serverID, bsize, self.URL))

                numFailedAttempts = 0

                # Record successful upload in storagemanager
                self.storageManager.setUploaded(self.serverID, eidlist)
                # Reduce counter
                self.numEventsLock.acquire()
                self.numEvents -= bsize
                self.numEventsLock.release()
            else:
                numFailedAttempts += 1

                msg1 = ("Error Uploader %i: %s: Return code: %s." %
                        (self.serverID, self.URL, returncode))
                log(msg1, severity=2)
                msg2 = ("Error Uploader %i: %d events attempted to upload, "
                        "number of failed attempts: %i." %
                        (self.serverID, bsize, numFailedAttempts))
                log(msg2, severity=2)
                msg3 = msg1 + "\n" + msg2
                nr = NagiosResult(2, msg3, "ServerCheck")
                self.nagiosPush.sendToNagios(nr)
                sleeptime = min(2 ** numFailedAttempts * self.retryAfter,
                                self.maxWait)
                log("Uploader %i: Sleeping for %f seconds." %
                    (self.serverID, sleeptime))
                sleep(sleeptime)
        log("Uploader %i: Thread stopped!" % self.serverID, severity=2)
