#!/usr/bin/env python

import glob, os, re, sys

NO = "\x1b[0;0m"
BR = "\x1b[0;01m"
RD = "\x1b[31;01m"
GR = "\x1b[32;01m"
YL = "\x1b[33;01m"
BL = "\x1b[34;01m"
MG = "\x1b[35;01m"
CY = "\x1b[36;01m"

MAX_SLOTS = 100

def hostname(): return os.popen('hostname -s').read().strip()

def stdout(s): sys.stdout.write(s)

def isbourne(shell): return shell == 'sh' or shell == 'bash' or shell == 'zsh'

def iscsh(shell): return shell == 'csh'
  
def isinit(name): return name == 'init' or name == 'deinit'

def isidentifier(id): return re.match('^[A-Za-z_][A-Za-z0-9_]*$', id)

ECOMMANDS = 'eh el em ei eq ep erp eep es en ev ec ex'.split()
def isreserved(s): return s in ECOMMANDS + [ 'e%d' % i for i in range(100) ]

def get_flags(argv):
  flags = {}
  while len(argv) and argv[0][0] == '-':
    arg = argv.pop(0)
    if arg[0] == '-':
      for c in arg[1:]:
        flags[c] = 1
  return flags

class BourneShell:
  eval_fmt = "eval \"%s\""
  setenv_fmt = "export %s='%s'\n"
  unsetenv_fmt = "unset %s\n"
  alias_fmt = "%s() {\n  %s \n}\n"
  projects_dir = "sh"

  def __init__(self, e):
    self.e = e

  def setenv(self, name, value):
    stdout(self.setenv_fmt % (name, value))
    
  def unsetenv(self, name):
    stdout(self.unsetenv_fmt % (name))
    
  def alias(self, name, value):
    testpath = os.path.realpath(os.path.expanduser(value))
    if os.path.isdir(testpath):
      stdout(self.alias_fmt % (name, 'cd "%s"' % value))
    else:
      stdout(self.alias_fmt % (name, value))
    
  def echo(self, s):
    stdout("echo '%s';\n" % s)

  def unalias(self, name):
    stdout('typeset -f %s >/dev/null && unset -f %s\n' % (name, name))

  def eval_alias(self, name, value):
    stdout('%s() {\n  eval "$(%s/e.py %s $*)"\n}\n' % (name, self.e.home, value))

  def setenv_alias(self, name, value):
    self.setenv(name, value)
    self.alias(name, value)

  def unsetenv_alias(self, name):
    self.unsetenv(name)
    self.unalias(name)

  def exec_alias(self, name):
    stdout(name + ';')
    
class CShell(BourneShell):
  setenv_fmt = "setenv %s \"%s\";"
  unsetenv_fmt = "unsetenv %s;"
  alias_fmt = "alias %s '%s';"
  unalias_fmt = 'unalias %s;'
  projects_dir = "csh"

  def unalias(self, name):
    stdout(self.unalias_fmt % name)

  def eval_alias(self, name, value):
    stdout('set e=(eval \\"\\`%s/e.py %s \\!\\*\\`\\");alias %s "$e";' 
        (self.e.home, value, name))

  def exec_alias(self, name):
    stdout('eval "$%s";' % (name))
    
class Slot:
  def __init__(self, proj, slot, value='', name=''):
    self.proj = proj
    self.slot = slot
    self.value = value
    self.name = name

  def names(self):
    names = []

    if self.value == '':
      return names

    # add <project>_e# to list
    names.append('%s_e%d' % (self.proj.name, self.slot))
    if self.proj == self.proj.e.current:
      names.append('e%d' % self.slot)

    name = self.name

    # valid name not being an e command
    if isreserved(name):
      self.proj.e.shell.echo(
          '%s slot %d in project %s is reserved. no env/alias created.' %
          (name, self.slot, self.proj.name))
      return names

    # if slot doesn't have a name, we are done.
    if not name:
      return names

    names.append('%s_%s' % (self.proj.name, name))

    # init type names are only add if project is current
    if isinit(name) and self.proj != self.proj.e.current:
      return names

    names.append(name)
    return names

  def add_environment(self):
    if self.value == '':
      return
    for name in self.names():
      self.proj.e.shell.setenv_alias(name, self.value)

  def delete_environment(self):
    for name in self.names():
      self.proj.e.shell.unsetenv_alias(name)

class Project:
  def __init__(self, e, name):
    self.e = e
    self.slots = []
    self.name = name
    self.read()

  def read(self):
    fname = '%s/%s.project' % (self.e.projects_dir, self.name)
    def splitvn(s):
      s = s.strip()
      c = s.rfind(',')
      if c > -1:
        return s[:c], s[c+1:]
      else:
        return s, ''
    if os.path.exists(fname):
      data = map(splitvn, open(fname).readlines())
      slot = 0
      for value, name in data:
        self.slots.append(Slot(self, slot, value, name))
        slot += 1
    else:
      self.slots.append(Slot(self, 0))

  def write(self):
    fname = '%s/%s.project' % (self.e.projects_dir, self.name)
    f = open(fname, 'w')
    # remove empty slots at end of project
    while len(self.slots) > 1 and self.slots[-1].value == '':
      self.slots.pop(-1)
    for slot in self.slots:
      f.write('%s,%s\n' % (slot.value, slot.name))
    f.close()
    
  def extend(self, sz):
    l = len(self.slots)
    if l > sz:
      return
    self.slots.extend([Slot(self, l+i) for i in range(sz-l)])

  def find_slot(self, name):
    for slot in self.slots:
      if slot.name == name:
        return slot
    return None

  def exec_current(self, name):
    if not self == self.e.current:
      return
    if self.find_slot(name):
      self.e.shell.exec_alias('%s_%s' % (self.name, name))

  def add_environment(self):
    for slot in self.slots:
      slot.add_environment()
    self.exec_current('init')

  def delete_environment(self):
    self.exec_current('deinit')
    for slot in self.slots:
      slot.delete_environment()

  def clear_name(self, name):
    for slot in range(len(self.slots)):
      if self.slots[slot].name == name:
        self.slots[slot].delete_environment()
        self.slots[slot] = Slot(self, slot, self.slots[slot].value, '')
        self.slots[slot].add_environment()

  def slot_store(self, slot, name, value):
    if slot >= MAX_SLOTS:
      self.e.shell.echo('invalid slot %d, max is %d' % (slot, MAX_SLOTS))
      return
    if name and not isidentifier(name):
      self.e.shell.echo('invalid name "%s", not an identifier' % name)
      return
    self.extend(slot+1)
    if name == None:
      name = self.slots[slot].name
    else: # remove duplicate name if it exists
      self.clear_name(name)
    if value == None:
      value = self.slots[slot].value
    self.slots[slot].delete_environment()
    if value != '':
      self.slots[slot] = Slot(self, slot, value, name)
      self.slots[slot].add_environment()
    else:
      del self.slots[slot]
    self.write()

  def slot_name(self, slot, name):
    self.slot_store(slot, name, None)

  def slot_value(self, slot, value):
    self.slot_store(slot, None, value)

  def exchange(self, fromslot, toslot):
    l = len(self.slots)
    if fromslot > l and toslot > l:
      self.e.shell.echo('invalid slots %d and %d max is %d' %
          (fromslot, toslot, l))
      return
    slots = self.slots
    toname = tovalue = fromname = fromvalue = ''
    if toslot < l:
      toname, tovalue = slots[toslot].name, slots[toslot].value
    if fromslot < l:
      fromname, fromvalue = slots[fromslot].name, slots[fromslot].value
    self.slot_store(toslot, fromname, fromvalue)
    self.slot_store(fromslot, toname, tovalue)
    self.write()
    
  def ls(self):
    shell = self.e.shell
    shell.echo('%s%-64s%s $name' % (YL, self.name, NO))
    for slot in self.slots:
      s = '%s%2d%s: ' % (CY, slot.slot, NO)
      if len(slot.value) > 60:
        s += '%-56s %s...%s ' % (slot.value[:56], RD, NO)
      else:
        s += '%-60s ' % slot.value
      if slot.name:
        s += '$%-10s' % slot.name
      else:
        s += ' ' * 11
      s += ' :%s%d%s' % (CY, slot.slot, NO)
      shell.echo(s)

class E:
  def __init__(self, argv):
    self.argv = argv
    self.home = os.environ.get('EHOME', os.path.expanduser('~/.e'))
    if not os.path.exists(self.home):
      os.mkdir(self.home)
    self.shell = self.setup_shell()
    self.projects_dir = self.home + '/' + self.shell.projects_dir
    if not os.path.exists(self.projects_dir):
      os.mkdir(self.projects_dir)
    self.vars = {}
    self.projects = self.read_projects()
    self.current = self.get_current_project()
    self.update_vars()

  def setup_shell(self):
    shell = os.path.basename(os.environ['SHELL'])
    if iscsh(shell):
      return CShell(self)
    else:
      return BourneShell(self)

  def read_projects(self):
    projects = {}
    for pname in glob.glob1(self.projects_dir, '*.project'):
      proj = os.path.basename(pname).replace('.project','')
      projects[proj] = Project(self, proj)
    return projects
    
  def get_current_project(self):
    cfile = '%s/current-%s' % (self.projects_dir, hostname())
    name = os.environ.get('EPROJECT')
    if name == None and os.path.exists(cfile):
      name = open(cfile).read().strip()
    else:
      name = 'default'
    proj = self.projects.get(name, None)
    if proj == None:
      proj = self.new_project(name)
    return proj

  def set_current_project(self, project, onlylocal=False):
    if not onlylocal:
      open(self.projects_dir + '/current-' + hostname(),'w').write(project.name+'\n')
    save = self.current
    save.delete_environment()
    self.current = project
    self.update_vars()
    save.add_environment()
    self.current.add_environment()
    self.shell.setenv('EPROJECT', self.current.name)

  def new_project(self, name):
    fname = self.projects_dir + '/' + name
    if os.path.exists(fname + '.oldproject'):
      os.rename(fname + '.oldproject', fname + '.project')
    self.projects[name] = Project(self, name)
    self.projects[name].write()
    return self.projects[name]

  def project_names(self):
    return sorted(self.projects.keys())

  def update_vars(self):
    self.vars = {}
    for name in self.project_names():
      for slot in self.projects[name].slots:
        if slot.name:
          self.vars[slot.name] = name
    for slot in self.current.slots:
      if slot.name:
        self.vars[slot.name] = self.current.name

  def init(self):
    shell = self.shell
    for command in ECOMMANDS:
      shell.eval_alias(command, command)

    self.current = self.get_current_project()
    # add projects in alphabetical order, then the current project
    for name in self.project_names():
      project = self.projects[name]
      if project != self.current:
        project.add_environment()
    self.current.add_environment()

    shell.setenv('EHOME', self.home)
    shell.setenv('EPROJECT', self.current.name)

    if type(shell) == CShell:
      shell.unsetenv('e')
    
  def ls(self):
    for name in self.project_names():
      project = self.projects[name]
      if project == self.current:
        leader, color = '>', YL
      else:
        leader, color = ' ', CY
      s = leader + '%2d ' + color + '%-20s ' + NO
      self.shell.echo(s % (len(project.slots), name))

  def eq(self):
    shell = self.shell
    shell.unsetenv('EPROJECT')
    shell.unsetenv('EHOME')
    for name in self.project_names():
      self.projects[name].delete_environment()
    for name in ECOMMANDS:
      shell.unalias(name)

  def ei(self):
    self.init()

  def eh(self):
    shell = self.shell
    lines = [
      CY+"ep "+YL+"[-[tc]] [project]"+NO+":",
      "\tdisplay projects, if "+YL+"project "+NO+
          "specified, set it to current",
      "\t(-c creates new, -t temporary current shell only)",
      CY+"erp "+NO+YL+"project"+NO+":",
      "\tremove "+YL+"project "+NO+"(if current, default selected)",
      CY+"eep "+NO+YL+"[project]"+NO+":",
      "\tedit "+YL+"project "+NO+"and reinit (default current)",
      CY+"ev "+NO+YL+"0-# [value]"+NO+":",
      "\tstore "+YL+"value "+NO+"to slot "+YL+"0-# "+NO+
          "(empty value clears)",
      CY+"en "+NO+YL+"0-# [name]"+NO+":",
      "\tmake env variable "+YL+"name "+NO+"point to slot "+YL+"#"+NO+
          " (empty name clears)",
      CY+"es "+NO+YL+"0-# [name] [value]"+NO+":",
      "\tmake slot "+YL+"# "+NO+"with "+YL+"name "+NO+"and "+
          YL+"value "+NO+"(empty name & value clears)",
      CY+"ec "+NO+YL+"name [value]"+NO+":",
      "\tmake slot with "+YL+"name "+NO+"and "+
          YL+"value "+NO+"(empty value clears)",
      CY+"el "+NO+YL+"[project]"+NO+":",
      "\tlist all slots titles in "+YL+"project "+NO+
          "(default current)",
      CY+"em "+NO+YL+"[-[Aac]]"+NO+":",
      "\tlist name,value,proj "+
          "(-a=all projs,-A=names & <proj>_<var>,-c=color)",
      CY+"ex "+NO+YL+"from to"+NO+":",
      "\texchange slots "+YL+"from "+NO+"and "+YL+"to"+NO,
      CY+"ei"+NO+":\n\t(re)initialize environment and alises",
      CY+"eq"+NO+":\n\tremove env and alises",
      CY+"eh"+NO+":\n\tprint this help message",
    ]
    for line in lines:
      shell.echo(line)

  def el(self):
    name = (self.argv + [''])[0]
    self.projects.get(name, self.current).ls()
    
  def em(self):
    flags = get_flags(sys.argv)

    if flags.get('a', 0) == 1:
      names = self.project_names()
      names.remove(self.current.name)
      names.append(self.current.name)
    else:
      names = [ self.current.name ]

    if flags.get('c', 0) == 1:
      fmt = CY + '$%s' + NO + ',%s,' + GR + '%s' + NO 
    else:
      fmt = '$%s,%s,%s'

    for name in names:
      project = self.projects[name]
      for slot in project.slots:
        if flags.get('A', 0) == 1:
          for var in slot.names():
            self.shell.echo(fmt % (var, slot.value, name))
        else:
          if slot.name:
            self.shell.echo(fmt % (slot.name, slot.value, name))

  def ep(self):
    flags = get_flags(sys.argv)
    if len(self.argv):
      name = self.argv.pop(0)
      if not isidentifier(name):
        self.shell.echo('invalid project name "%s", not an identifier' % name)
        return

      if flags.get('c', 0):
        proj = self.new_project(name)
      else:
        proj = self.projects.get(name, None)

      if proj:
        self.set_current_project(proj, flags.get('t', 0)) 
        self.ls()
      else:
        self.shell.echo('no project named "%s", use "ep -c %s" to create' %
                (name, name))
    else:
      self.ls()

  def erp(self):
    if len(self.argv) == 0:
      self.shell.echo('usage: erp project')
      return

    name = self.argv[0]
    if name == 'default':
      self.shell.echo('cannot remove project "default"')
      return

    if not self.projects.has_key(name):
      self.shell.echo('project "%s" does not exist' % name)
      return

    self.projects[name].delete_environment()
    if self.projects[name] == self.current:
      self.set_current_project(self.projects['default'])
    del self.projects[name]

    fname = self.projects_dir + '/' + name
    os.rename(fname + '.project', fname + '.oldproject')

    self.ls()

  def eep(self):
    name = self.current.name 
    if len(self.argv):
      name = self.argv.pop(0)
      if not self.projects.has_key(name):
        self.projects[name] = Project(self, name)
    self.projects[name].delete_environment()
    fname = self.projects_dir + '/' + name + '.project'
    stdout('%s %s;ei\n' % (os.environ['EDITOR'], fname))

  def es(self):
    if len(self.argv) < 1:
      self.shell.echo('usage: es slot [name] [value]')
      return
    slot = int(sys.argv.pop(0))
    name = value = ''
    if len(self.argv):
      name = sys.argv.pop(0)
    if len(self.argv):
      value = ' '.join(sys.argv)
    self.current.slot_store(slot, name, value.strip())

  def en(self):
    if len(self.argv) < 1:
      self.shell.echo('usage: en slot [name]')
      return
    slot = int(self.argv.pop(0))
    name = ''
    if len(self.argv):
      name = self.argv.pop(0)
    self.current.slot_name(slot, name)

  def ev(self):
    if len(self.argv) < 1:
      self.shell.echo('usage: ev slot [value]')
      return
    slot = int(self.argv.pop(0))
    value = ''
    if len(self.argv):
      value = ' '.join(self.argv)
    self.current.slot_value(slot, value)

  def ec(self):
    if len(self.argv) < 1:
      self.shell.echo('usage: ec name [value]')
      return
    name = self.argv.pop(0)
    value = ''
    if len(self.argv):
      value = ' '.join(self.argv)
    for slot in self.current.slots:
      if slot.name == name:
        self.current.slot_value(slot.slot, value)

  def ex(self):
    if len(self.argv) < 2:
      self.shell.echo('usage: ex # #')
      return
    fromslot, toslot = map(int, self.argv[:2])
    self.current.exchange(fromslot, toslot)

  def process(self):
    cmd = self.argv.pop(0)
    if hasattr(self, cmd):
      eval('self.%s()' % cmd)
    else:
      self.shell.echo('invalid command "%s"' % cmd)

def main(argv):
  prog = argv.pop(0)
  e = E(argv)
  sys.exit(e.process())

if __name__ == '__main__':
  main(sys.argv)

# vim: sw=2 :
