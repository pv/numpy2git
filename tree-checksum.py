#!/usr/bin/env python
"""
Usage: tree-checksum.py [--all-git|--all-svn] DIRECTORY > LISTING
       tree-checksum.py --compare ORIGINAL CONVERTED

Compute a checksum for a directory (or for svn-all-fast-export / SVN items).

"""
import optparse
import tempfile
import sys
import os
import re
import hashlib
import shutil
import subprocess

KEYWORD_STRIP_SCRIPT = os.path.abspath(os.path.join(os.path.dirname(__file__),
                                                    'svn-kill-keywords.py'))

def main():
    p = optparse.OptionParser(usage=__doc__.strip())
    p.add_option("--all-git", action="store_true")
    p.add_option("--all-svn", action="store_true")
    p.add_option("--start-rev", action="store", type="int")
    p.add_option("--compare", action="store_true")
    options, args = p.parse_args()

    if options.compare:
        if len(args) != 2:
            p.error("invalid number of arguments")
        equal = do_compare(args[0], args[1])
        sys.exit(0 if equal else 1)

    if len(args) != 1:
        p.error("invalid number of arguments")

    path = args[0]

    if options.all_git:
        do_git(path, start_rev=options.start_rev)
    elif options.all_svn:
        do_svn(path, start_rev=options.start_rev)
    else:
        print path_checksum(path)
    sys.exit(0)

def _with_workdir(func):
    def wrapper(*a, **kw):
        tmpdir = os.path.abspath(tempfile.mkdtemp())
        try:
            a = a + (tmpdir,)
            func(*a, **kw)
        finally:
            shutil.rmtree(tmpdir)
    return wrapper

def do_compare(original_filename, converted_filename, start_rev=None):
    original = _read_listing(original_filename)
    converted = _read_listing(converted_filename)

    states = original.keys()
    states.sort()

    converted_checksums = {}
    for (rev, branch), checksum in converted.items():
        converted_checksums[checksum] = True

    equal = True

    for state in states:
        if state in converted:
            if original[state] != converted[state]:
                equal = False
                print "MISMATCH ", state[0], state[1]
        else:
            # The converted repo contains commits only for those SVN commits
            # that actually change something. So report missing states
            # only if the tree checksum does not appear at all in the converted
            # repo.
            if original[state] not in converted_checksums:
                print "MISSING  ", state[0], state[1]

    states = converted.keys()
    states.sort()
    for state in states:
        if state not in original:
            print "spurious ", state[0], state[1]

    return equal

def _read_listing(filename):
    listing = {}
    f = open(filename, 'r')
    try:
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split()
            if len(parts) != 3:
                raise ValueError("Invalid line '%s'" % line)
            listing[(int(parts[0]), parts[1])] = parts[2]
    finally:
        f.close()
    return listing

@_with_workdir
def do_git(path, workdir, start_rev=None):
    repo = os.path.join(workdir, 'repo')
    git('clone', '--quiet', path, repo)
    os.chdir(repo)
    git('fetch', '--quiet', 'origin', 'refs/*:refs/remotes/origin/*')

    for commit in git.readlines('log', '--format=%H', '--all'):
        msg = git.readlines('cat-file', 'commit', commit)
        m = re.match(r'svn path=/(.*)/; revision=(\d+)', msg[-1].strip())
        assert m is not None, commit

        if start_rev is not None and int(m.group(2)) > start_rev:
            continue

        git('checkout', '--quiet', commit)

        checksum = path_checksum(repo)
        print m.group(2), m.group(1), checksum
        sys.stdout.flush()

@_with_workdir
def do_svn(path, workdir, start_rev=None):
    if '://' in path:
        url = path
    else:
        url = ("file://" +
               os.path.normpath(os.path.abspath(path)).replace(os.path.sep, '/').rstrip('/'))

    checkoutdir = os.path.join(workdir, 'repo')

    for commit, branch in svn_logreader(url):
        if start_rev is not None and commit > start_rev:
            continue

        commiturl = url + '/' + branch + ("@%s" % commit)
        if not os.path.isdir(checkoutdir):
            svn('checkout', '--ignore-externals', '-q', '-r', str(commit),
                commiturl, checkoutdir)
            os.chdir(checkoutdir)
        else:
            os.chdir(checkoutdir)
            svn('revert', '-q', '-R', '.')
            svn('switch', '--force', '--ignore-externals', '-q', commiturl)
        subprocess.call([KEYWORD_STRIP_SCRIPT])

        checksum = path_checksum(checkoutdir)
        print commit, branch, checksum
        sys.stdout.flush()
            
def svn_logreader(url):
    """
    Read commit+branch information from SVN log.

    """
    log = svn.pipe('log', '-v', url)

    seen = {}

    while log:
        line = log.readline()
        if line.startswith('-'*50):
            line = log.readline().strip()
            if not line:
                break
            m = re.match('^r(\d+) .*', line)
            commit = int(m.group(1))

            line = log.readline().strip()
            assert line.startswith('Changed paths:')

            while log:
                line = log.readline().strip()
                if not line:
                    break

                m = re.match(r'^[MARD]\s+/(.*)', line)
                pth = m.group(1)
                m = re.match(r'^(branches/[^/ ]+|tags/[^/ ]+|trunk).*?', pth)
                if m:
                    branch = m.group(1)
                    key = (commit, branch)
                    if key not in seen:
                        seen[key] = True
                        if line != "D /%s" % m.group(1):
                            # skip whole-branch deletions
                            yield commit, m.group(1)


def path_checksum(path):
    digest = hashlib.sha1()

    def feed_file(filename):
        f = open(filename, 'rb')
        try:
            while True:
                chunk = f.read(65536)
                if not chunk:
                    break
                digest.update(chunk)
        finally:
            f.close()

    def feed_string(s):
        digest.update(s)

    for dirpath, dirnames, filenames in os.walk(path, topdown=True):
        dirnames.sort()
        for name in ('.svn', '.git'):
            try:
                dirnames.remove(name)
            except ValueError:
                pass

        filenames.sort()
        for fn in filenames:
            feed_string(fn)
            feed_file(os.path.join(dirpath, fn))

    return digest.hexdigest()


#------------------------------------------------------------------------------
# Communicating with Git/SVN
#------------------------------------------------------------------------------

class Cmd(object):
    executable = None

    def __init__(self, executable):
        self.executable = executable

    def _call(self, command, args, kw, repository=None, call=False):
        cmd = [self.executable, command] + list(args)
        cwd = None

        if repository is not None:
            cwd = os.getcwd()
            os.chdir(repository)

        try:
            if call:
                return subprocess.call(cmd, **kw)
            else:
                return subprocess.Popen(cmd, **kw)
        finally:
            if cwd is not None:
                os.chdir(cwd)

    def __call__(self, command, *a, **kw):
        ret = self._call(command, a, {}, call=True, **kw)
        if ret != 0:
            raise RuntimeError("%s failed" % self.executable)

    def pipe(self, command, *a, **kw):
        stdin = kw.pop('stdin', None)
        p = self._call(command, a, dict(stdin=stdin, stdout=subprocess.PIPE),
                      call=False, **kw)
        return p.stdout

    def read(self, command, *a, **kw):
        p = self._call(command, a, dict(stdout=subprocess.PIPE),
                      call=False, **kw)
        out, err = p.communicate()
        if p.returncode != 0:
            raise RuntimeError("%s failed" % self.executable)
        return out

    def readlines(self, command, *a, **kw):
        out = self.read(command, *a, **kw)
        return out.rstrip("\n").split("\n")

    def test(self, command, *a, **kw):
        ret = self._call(command, a, dict(stdout=subprocess.PIPE,
                                          stderr=subprocess.PIPE),
                        call=True, **kw)
        return (ret == 0)

git = Cmd("git")
svn = Cmd("svn")


#------------------------------------------------------------------------------

if __name__ == "__main__":
    main()
