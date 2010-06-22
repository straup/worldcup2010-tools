#!/usr/bin/env python

# usage:
# $> python ./guardian_relay -c guardian.cfg

import logging
import sys
import urllib2
import time
import os.path
import tempfile
import xmpp

try:
    import json
except Exception, e:
    import simplejson as json

class relay:

    def __init__ (self, cfg):

        self.cfg = cfg

        self.updates = cfg.get('guardian', 'updates_url')
        self.localstore = os.path.join(tempfile.gettempdir(), 'updates_seen.json')
        self.seen = {}

        if os.path.exists(self.localstore):
            self.seen = self.load_seen(self.localstore)

        self.droid = None
        self.gtalk = None

        try:
            import android
            self.droid = android.Android()
        except Exception, e:
            pass

        try:
           if self.cfg.get('guardian', 'use_gtalk'):

                self.from_user = self.cfg.get('gtalk', 'from_user')
                self.from_pswd = self.cfg.get('gtalk', 'from_pswd')
                self.to_user = self.cfg.get('gtalk', 'to_user')

                # I don't know. You tell me why this is necessary...

                self.from_user = self.from_user.replace('@gmail.com', '')

                self.gtalk = xmpp.Client('gmail.com')
                self.gtalk.connect(server=('talk.google.com',5223))
                self.gtalk.auth(self.from_user, self.from_pswd, 'guardian_relay.py')
        except Exception, e:
            self.error('failed to enable gtalk: %s' % e)

    def run (self, tts=60):

        while True:
            self.display_updates()
            time.sleep(tts)

    def load_seen(self, path):

        fh = open(path, 'r')
        seen = json.load(fh)
        fh.close()
        return seen

    def write_seen(self, path, seen):
        fh = open(path, 'w')
        fh.write(json.dumps(seen, indent=0))
        fh.close()

    def error(self, msg):

        if self.droid:
            sys.stderr.write("[error] %s" % msg)
            return

        logging.error(msg)

    def display_updates(self):

        count_new = 0

        try:
            rsp = urllib2.urlopen(self.updates)
        except Exception, e:
            logging.error("failed to fetch %s: %s" % (self.updates, e))
            return False

        try:
            data = json.loads(rsp.read())
        except Exception, e:
            self.error("failed to parse updates: %s" % e)
            return False

        for event, details in data.items():

            for post in details['updates']:

                if not post:
                    continue

                hex, text = post

                if self.seen.get(hex, False):
                    self.error("skipping %s" % hex)
                    continue

                try:
                    self.notify(text)
                    count_new += 1
                except Exception, e:
                    self.error('failed to notify: %s' % )

                self.seen[hex] = int(time.time())

        if count_new:
            self.write_seen(self.localstore, self.seen)

    def notify(self, text):

        text = text.encode('ascii', 'replace')

        if self.droid:
            self.droid.notify('guardian world cup chatter', text)

	if self.gtalk:
            import xmpp
            self.gtalk.send(xmpp.Message(self.to_user, text))

        sys.stdout.write(text)

if __name__ == '__main__':

    import optparse
    import ConfigParser

    parser = optparse.OptionParser()
    parser.add_option('-c', dest='config', action='store')
    opts, args = parser.parse_args()

    cfg = ConfigParser.ConfigParser()
    cfg.read(opts.config)

    r = relay(cfg)
    r.run()
