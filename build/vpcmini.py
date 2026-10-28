#!/usr/bin/env python3
import sys, re, os

DEFAULT_DEFINES = set([
    'POSIX', 'LINUX', 'LINUXALL', 'LINUX64', 'GNUC', '_LINUX',
    'PLATFORM_64BITS', 'X64BITS', 'COMPILER_GCC', 'CROSS_PLATFORM_VERSION',
])

def cond_true(cond, defines):
    if not cond:
        return True
    s = cond
    if '[' in s:
        try:
            s = s[s.index('[') + 1:s.rindex(']')]
        except ValueError:
            pass
    s = re.sub(r'\$([A-Za-z0-9_]+)', lambda m: '1' if m.group(1) in defines else '0', s)
    s = s.replace('&&', ' and ').replace('||', ' or ')
    s = re.sub(r'!', ' not ', s)
    try:
        return bool(eval(s))
    except Exception:
        return False

def strip_comment(line):
    # remove // comments not inside quotes
    out = []
    inq = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"':
            inq = not inq
        if not inq and c == '/' and i + 1 < len(line) and line[i + 1] == '/':
            break
        out.append(c)
        i += 1
    return ''.join(out)

def last_cond(line):
    # return the last [...] group, and the line with it removed
    m = None
    for mm in re.finditer(r'\[[^\]]*\]', line):
        m = mm
    if not m:
        return None, line
    return m.group(0), (line[:m.start()] + line[m.end():])

class Parser:
    def __init__(self, root, defines):
        self.root = os.path.normpath(root)  # repo dir (c15)
        self.defines = set(defines)
        self.macros = {}
        self.files = []
        self.seen = set()
        self.incs = []
        self.ppdefs = []

    def abspath(self, base_dir, p):
        p = p.replace('\\', '/')
        # expand known macros used in paths
        p = re.sub(r'\$SRCDIR', self.macros.get('SRCDIR', '..'), p)
        p = re.sub(r'\$([A-Za-z0-9_]+)', lambda m: self.macros.get(m.group(1), ''), p)
        if p.startswith('/'):
            full = p
        else:
            full = os.path.join(base_dir, p)
        return os.path.normpath(full)

    def rel(self, full):
        return os.path.relpath(full, self.root).replace('\\', '/')

    def tokenize_paths(self, line):
        return re.findall(r'"([^"]+)"', line)

    def parse(self, path, parent_eff=True):
        path = os.path.normpath(path)
        if not os.path.exists(path):
            return
        try:
            text = open(path, 'r', errors='replace').read()
        except Exception:
            return
        text = text.replace('\\\n', ' ')
        lines = text.split('\n')
        cur_dir = os.path.dirname(path)
        stack = [parent_eff]
        pending_cond = True
        for raw in lines:
            line = strip_comment(raw).strip()
            if line == '':
                continue
            cond, line2 = last_cond(line)
            cval = cond_true(cond, self.defines) if cond else pending_cond
            eff = stack[-1] and cval
            if line2.strip() == '{' or line2.rstrip().endswith('{'):
                # block open; cond already captured
                stack.append(eff)
                pending_cond = True
                continue
            if line2.strip() == '}':
                if len(stack) > 1:
                    stack.pop()
                pending_cond = True
                continue
            top = stack[-1]
            ll = line2.lower()
            if line2.lstrip().startswith('$') and 'additionalincludedirector' in ll:
                if eff:
                    for s in self.tokenize_paths(line2):
                        for part in re.split(r'[;,]', s):
                            part = part.strip()
                            if not part:
                                continue
                            full = self.abspath(cur_dir, part)
                            rel = self.rel(full)
                            if rel not in self.incs:
                                self.incs.append(rel)
                pending_cond = True
                continue
            if line2.lstrip().startswith('$') and 'preprocessor' in ll:
                if eff:
                    for s in self.tokenize_paths(line2):
                        for part in re.split(r'[;,]', s):
                            part = part.strip()
                            if not part or part.startswith('$'):
                                continue
                            if part not in self.ppdefs:
                                self.ppdefs.append(part)
                pending_cond = True
                continue
            if line2.lstrip().startswith('$'):
                if '$include' in ll:
                    if eff:
                        for p in self.tokenize_paths(line2):
                            inc = self.abspath(cur_dir, p)
                            self.parse(inc, eff)
                    pending_cond = True
                    continue
                if '$macro' in ll and '$macrorequired' not in ll:
                    if eff:
                        m = re.match(r'\s*\$Macro\s+([A-Za-z0-9_]+)\s+"([^"]*)"', line2, re.IGNORECASE)
                        if m:
                            name, val = m.group(1), m.group(2)
                            if name == 'SRCDIR':
                                val = os.path.abspath(os.path.join(cur_dir, val.replace('\\', '/')))
                            self.macros[name] = val
                    pending_cond = True
                    continue
                if ll.lstrip().startswith('-$file'):
                    if eff:
                        for p in self.tokenize_paths(line2):
                            f = self.rel(self.abspath(cur_dir, p))
                            if f in self.files:
                                self.files.remove(f)
                    pending_cond = True
                    continue
                if ll.lstrip().startswith('$file'):
                    if eff and '$configuration' not in ll:
                        for p in self.tokenize_paths(line2):
                            f = self.rel(self.abspath(cur_dir, p))
                            if f not in self.seen:
                                self.seen.add(f)
                                self.files.append(f)
                    pending_cond = True
                    continue
                # other block keyword ($Folder/$Project/$Configuration/...)
                pending_cond = cval
                continue
            pending_cond = True

def main():
    root = sys.argv[1]          # e.g. c15
    proj = sys.argv[2]          # e.g. tier0/tier0.vpc
    mode = sys.argv[3] if len(sys.argv) > 3 else '--files'
    defines = DEFAULT_DEFINES
    projpath = os.path.normpath(os.path.join(root, proj))
    # pre-read SRCDIR macro from the project vpc
    srcroot = os.path.dirname(projpath)
    srdir = '..'
    try:
        txt = open(projpath, errors='replace').read()
        m = re.search(r'\$Macro\s+SRCDIR\s+"([^"]*)"', txt)
        if m:
            srdir = m.group(1).replace('\\', '/')
    except Exception:
        pass
    p = Parser(root, defines)
    p.macros['SRCDIR'] = os.path.abspath(os.path.join(srcroot, srdir))
    p.parse(projpath, True)
    if mode == '--defs':
        print(';'.join(p.ppdefs))
    elif mode == '--inc':
        for i in p.incs:
            print(i)
    else:
        for f in p.files:
            print(f)

if __name__ == '__main__':
    main()
