#!/usr/bin/env python
"""
Usage: tree-checksum.py DIRECTORY

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


def main():
    p = optparse.OptionParser(usage=__doc__.strip())
    p.add_option("--all-git", action="store_true")
    p.add_option("--all-svn", action="store_true")
    options, args = p.parse_args()

    if len(args) != 1:
        p.error("invalid number of arguments")

    path = args[0]

    if options.all_git:
        do_git(path)
    elif options.all_svn:
        do_svn(path)
    else:
        print path_checksum(path)
    sys.exit(0)

def _with_workdir(func):
    def wrapper(*a, **kw):
        if os.path.isdir('/dev/shm'):
            tmpdir = os.path.abspath(tempfile.mkdtemp(dir='/dev/shm'))
        else:
            tmpdir = os.path.abspath(tempfile.mkdtemp())
        try:
            a = a + (tmpdir,)
            func(*a, **kw)
        finally:
            shutil.rmtree(tmpdir)
    return wrapper

@_with_workdir
def do_git(path, workdir):
    repo = os.path.join(workdir, 'repo')
    git('clone', '--quiet', path, repo)
    os.chdir(repo)

    for commit in git.readlines('log', '--format=%H', '--all'):
        git('checkout', '--quiet', commit)
        checksum = path_checksum(repo)

        msg = git.readlines('cat-file', 'commit', commit)
        m = re.match(r'svn path=/(.*)/; revision=(\d+)', msg[-1].strip())
        assert m is not None, commit

        print m.group(2), m.group(1), checksum
        sys.stdout.flush()

@_with_workdir
def do_svn(path, workdir):
    url = "file://" + \
          os.path.normpath(os.path.abspath(path)).replace(os.path.sep, '/').rstrip('/')

    branchdirs = {}

    for commit, branch in svn_logreader(url):
        if branch not in branchdirs:
            dirname = branch.replace('/', '-')
            branchdirs[branch] = os.path.join(workdir, dirname)
            svn('checkout', '-q', '-r', str(commit),
                url + '/' + branch, branchdirs[branch])
            os.chdir(branchdirs[branch])
        else:
            os.chdir(branchdirs[branch])
            svn('update', '-q', '-r', str(commit))
            svn('revert', '-q', '-R', '.')

        checksum = path_checksum(branchdirs[branch])
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
                m = re.match(r'^(branches/[^/ ]+|trunk).*?', pth)
                if m:
                    branch = m.group(1)
                    key = (commit, branch)
                    if key not in seen:
                        seen[key] = True
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
