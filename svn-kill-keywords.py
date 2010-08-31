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
    for fn, keywords in sorted(targets.items()):
        svn_base_fn = os.path.join(os.path.dirname(fn), '.svn', 'text-base',
                                   os.path.basename(fn) + '.svn-base')
        shutil.copyfile(svn_base_fn, fn)

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
