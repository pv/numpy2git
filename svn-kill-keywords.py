#!/usr/bin/env python
"""
svn-kill-keywords.py

Strip SVN keywords from files in the current working tree.

"""
import os
import re
import optparse
import subprocess
import tempfile
import shutil
import sys
from xml.etree import ElementTree as etree

def main():
    p = optparse.OptionParser(usage=__doc__.strip())
    options, args = p.parse_args()

    if len(args) != 0:
        p.error('invalid arguments')

    # Find files with keywords
    targets = find_targets()

    # Strip keywords from files
    for fn, keywords in targets.items():
        strip_keywords(fn, keywords)

def strip_keywords(filename, keywords):
    kw = re.compile('\\$((%s):?)[^\\$\n]+?\\$' % '|'.join(keywords), re.S)

    f = open(filename, 'rb')
    data = f.read()
    f.close()

    data = kw.sub(r'$\1$', data)

    fd, tmpfn = tempfile.mkstemp()
    os.write(fd, data)
    os.close(fd)

    shutil.move(tmpfn, filename)

def find_targets():
    s = subprocess.Popen(['svn', 'pg', '-R', '--xml', 'svn:keywords'],
                         stdout=subprocess.PIPE)

    targets = {}
    keywords = []
    for ev, elem in etree.iterparse(s.stdout):
        if elem.tag == "target":
            if keywords:
                targets[elem.attrib['path']] = keywords
            keywords = []
        elif elem.tag == "property":
            if elem.attrib['name'] == 'svn:keywords':
                keywords = elem.text.split()
    return targets

if __name__ == "__main__":
    main()
