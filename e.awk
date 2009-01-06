#!/bin/awk -f

# globals:
#  ehome - environment variable $EHOME
#  eproj - <ehome>/<hostname>-currentproject
#  evalues - environment values
#  enames - environment names
#  emax - number of entries

function getopt_single(arg, flag, opts, flags,  o)
{
  for (o=1; o<=length(opts); o++) {
    if (substr(opts, o, 1) == flag) {
      flags[flag] = substr(opts, o+1, 1) == ":" ? ARGV[++arg] : 1;
    } 
  }
  return arg;
}

function getopt(arg, opts, flags, args,  a, i, s, flag)
{
  for (a=0 ;arg < ARGC; arg++) {
    if (substr(ARGV[arg], 1, 1) != "-") {
      args[a++] = ARGV[arg];
      continue;
    }
    s = substr(ARGV[arg], 2);
    for (i=1; i<=length(s); i++) {
      flag = substr(s, i, 1);
      arg = getopt_single(arg, flag, opts, flags);
    }
  }
}

function join(strs, sep,  s, i, n)
{
   n = asort(strs);
   for (i=1; i<=n; i++) {
     s = s sep strs[i];
   }
   return substr(s, 2);
}

function pipe(cmd,  val)
{
  cmd | getline val;
  close(cmd);
  return val
}

function hostname(  host)
{
  return pipe("hostname -s");
}

function shell(  sh)
{
  return pipe("basename $SHELL");
}

function isbourne(shell)
{
  return shell == "zsh" || shell == "bash" || shell == "sh";
}

function iscsh(shell)
{
  return shell == "csh";
}

function isidentifier(s)
{
  return s ~ "[A-Za-z_][A-Za-z0-9_]*";
}

function isdir(s,  cmd, type)
{
  #rc = system(sprintf("test -d '%s'",s));
  #return rc == 0
  cmd = sprintf("stat -L -c '%%F' '%s' 2>/dev/null", s);
  cmd | getline type;
  close(cmd);
  return type == "directory";
}

function set_formats()
{
  eevalfmt = "eval \"%s\"";
  if (isbourne(shell())) {
    esetenvfmt = "export %s='%s'\n";
    eunsetenvfmt = "unset %s\n";
    ealiasfmt = "%s() {\n  %s \n}\n";
  } else if (iscsh(shell())) {
    esetenvfmt = "setenv %s \"%s\";";
    eunsetenvfmt = "unsetenv %s;";
    ealiasfmt = "alias %s '%s';";
  }
}

function echo(s)
{
  printf("echo '%s';\n", s);
}

function setenv(name, value)
{
  #echo(sprintf("setenv %s %s", name, value));
  printf(esetenvfmt, name, value);
}

function unsetenv(name)
{
  #echo(sprintf("unsetenv %s", name));
  printf(eunsetenvfmt, name);
}

function aliaseval(name, value)
{
  #echo(sprintf("aliaseval %s %s", name, value));
  if (isbourne(shell())) {
    printf("%s() {\n  eval \"$(%s/e.awk %s $*)\"\n}\n",
	   name, ehome, value);
  } else if (iscsh(shell())) {
    printf("set e=(eval \\\"\\`%s/e.awk %s \\\\!\\*\\`\\\");alias %s \"$e\";",
	   ehome, value, name);
  }
}

function alias(name, value)
{
  #echo(sprintf("alias %s %s", name, value));
  if (isdir(value)) {
    printf(ealiasfmt, name, "cd " value);
  } else {
    printf(ealiasfmt, name, value);
  }
}

function unalias(name)
{
  #echo(sprintf("unalias %s %s", name));
  if (isbourne(shell())) {
    printf("typeset -f %s >/dev/null && unset -f %s\n", name, name);
  } else if (iscsh(shell())) {
    printf("unalias %s;", name);
  }
}

function setenvalias(name, value)
{
  setenv(name, value);
  alias(name, value);
}

function unsetenvalias(name)
{
  unsetenv(name);
  unalias(name);
}

function isreserved(value)
{
  for (i in ecommands) {
    command = ecommands[i]
    if (command == value) {
      return command;
    }
  }
  for (i=0; i<emax; i++) {
    if ("e" i == value) {
      return "e" i;
    }
  }
  return "";
}

function get_current_project(useenv,  file)
{
  eproj = ENVIRON["EPROJECT"];
  if (!eproj || !useenv) {
    file = ehome "/current-" hostname();
    if ((getline eproj < file) < 0) {
      eproj = "default"
      set_current_project(eproj);
    }
    close(file);
  }
}

function set_current_project(proj,  file)
{
  file = ehome "/current-" hostname();
  printf("%s\n", proj) > file;
  close(file);
}

function read_project(proj, values, names,  projfile, i, j, last)
{
  delete values;
  delete names;
  FS = ",";
  i = 0;
  last = 0;
  projfile = ehome "/" proj ".project";
  while ((getline < projfile) > 0) {
    values[i] = $1;
    for(j=2; j<NF; j++) {
      values[i] = values[i] "," $j;
    }
    if (values[i]) {
      last = i;
    }
    names[i++] = $NF;
  }
  close(projfile);
  return last + 1;
}

function write_project(proj, values, names, n,  projfile, i)
{
  projfile = ehome "/" proj ".project";
  for(i=0;i<n;i++) {
    printf("%s,%s\n", values[i], names[i]) > projfile;
  }
  close(projfile);
}

function projects_list(projs,  i, cmd)
{
  FS="/";
  i = 0
  delete projs
  cmd = "ls " ehome "/*.project";
  while (cmd|getline) {
    gsub("\\.project", "", $NF);
    projs[i++] = $NF;
  }
  close(cmd);
  return i;
}

function isinit(name)
{
  return (name == "init" || name == "deinit") ? 1 : 0;
}

function add_env(proj, entry, name, value)
{
  if (value) {
    setenvalias(proj "_e" entry, value);
  }
  if (name) {
    if (isreserved(name)) {
      echo(sprintf("%s slot %d is project %s reserved. no env created",
 		name, entry, eproj));
      return;
    }
    setenvalias(proj "_" name, value);
    if (proj != eproj && isinit(name)) {
      return;
    }
    setenvalias(name, value);
  }
}

function delete_env(proj, entry, name)
{
  unsetenvalias(proj "_e" entry);
  if (name) {
    unsetenvalias(proj "_" name);
    if (proj != eproj && isinit(name)) {
      return;
    }
    unsetenvalias(name);
  }
}

function delete_evars(env,  i, names)
{
  split(env, names, ",");
  for (i in names) {
    unsetenvalias(names[i]);
  }
}

function add_environment(entry)
{
  if (evalues[entry]) {
    setenvalias("e" entry, evalues[entry]);
  }
  add_env(eproj, entry, enames[entry], evalues[entry]);
}

function delete_environment(entry)
{
  unsetenvalias("e" entry);
  delete_env(eproj, entry, enames[entry]);
}

function add_project_environment(proj,  names, values, n, i)
{
  n = read_project(proj, values, names);
  for (i=0; i<n; i++) {
    add_env(proj, i, names[i], values[i]);
  }
}

function delete_project_environment(proj,  names, values, n, i)
{
  if (ENVIRON["EPROJECTS_" proj]) {
    delete_evars(ENVIRON["EPROJECTS_" proj]);
  } else {
    echo("EPROJECTS_" proj " does not exists, cannot delete project vars");
  }
}

function list_projects(  proj, leader, projs, i, n, names, values)
{
  projects_list(projs); 
  for (i in projs) {
    n = read_project(projs[i], values, names);
    if (eproj == projs[i]) {
      leader = ">";
      color = YL;
    } else {
      leader = " ";
      color = CY;
    }
    echo(sprintf(leader "%2d " color "%-20s " NO, n, projs[i]));
  }
}

function add_current_project(  i)
{
  for(i=0; i<emax; i++) {
    add_environment(i);
  }

  for(i=0; i<emax; i++) {
    if (enames[i] == "init") {
      printf("%s;", eproj "_" enames[i]);
    }
  }
}

function clear_current_project(  i)
{
  for(i=0; i<emax; i++) {
    if (enames[i] == "deinit") {
      printf("%s;", enames[i]);
    }
  }

  delete_evars(ENVIRON["EPROJECTS_" eproj]);
  add_project_environment(eproj);
}

function select_project(proj, temp, i, projfile)
{
  clear_current_project();

  eproj = proj
  setenv("EPROJECT", eproj);

  proj = ehome "/" eproj
  projfile = proj ".project";
  if ((getline < sprintf("%s.oldproject", proj)) > 0) {
    system("mv " proj ".oldproject " projfile);
  }

  emax = read_project(eproj, evalues, enames);
  write_project(eproj, evalues, enames, emax);

  add_current_project();
  if (!temp) {
    set_current_project(eproj);
  }
}

function projects(arg,   args, flags, proj, projnm, n)
{
  getopt(arg, "t", flags, args);
  proj = args[0];
  if (proj && !isidentifier(proj)) {
    echo("invalid project name \"" proj "\"");
    return;
  }
  if (proj && proj != eproj) {
    select_project(proj, flags["t"])
  }
  list_projects();
}

function rm(arg,  proj)
{
  if (arg >= ARGC) {
    echo("usage: erp project");
    return;
  }
  proj = ARGV[arg++];
  if (proj == "default") {
    echo("cannot remove default project '" proj "'");
    return;
  }
  delete_project_environment(proj);
  cmd = sprintf("/bin/mv %s/%s.project %s/%s.oldproject",
	ehome, proj, ehome, proj);
  if (system(cmd)) {
    echo("cannot rename project '" proj "'");
  }
  unsetenv("EPROJECTS_" proj);
  if (proj == eproj) {
    select_project("default");
  }
  list_projects();
}

function edit(arg,  proj)
{
  proj = ARGV[arg++];
  if (!proj) {
    proj = eproj;
  }
  if (proj == eproj) {
    clear_current_project();
  } else {
    delete_project_environment(proj);
  }
  printf("%s %s;ei\n", ENVIRON["EDITOR"], ehome "/" proj ".project");
}

function remove_name(name,  i)
{
  for (i=0; i<emax; i++) {
    if (enames[i] == name) {
      delete_environment(i);
      enames[i] = "";
      add_environment(i);
    }
  }
}

function add_name_value(entry, newname, newvalue)
{
  # validate name
  if (newname) {
    if (newvalue == newname) {
      echo("invalid name '" newname "' cannot be same as value");
      return;
    }
    if (isreserved(newname)) {
      echo("invalid name '" newname "' for entry " entry " is reserved");
      return;
    }
    if (!isidentifier(newname)) {
      echo("invalid name " newname);
      return;
    }
  }
  if (entry > 99) {
    echo("invalid entry " entry ". max is 99");
    return;
  }

  echo("slot " entry " \"" newname "\" \"" newvalue "\" to project " eproj)
  remove_name(newname);
  if (entry < emax) {
    delete_environment(entry);
  }
  evalues[entry] = newvalue;
  enames[entry] = newname;
  add_environment(entry);
  if (entry >= emax) {
    emax = entry + 1;
  }
  write_project(eproj, evalues, enames, emax);
}

function get_value(arg,  newvalue)
{
  newvalue = ARGV[arg++];
  for (; arg<ARGC; arg++) {
    newvalue = newvalue " " ARGV[arg];
  }
  return newvalue;
}

function store(arg,  entry, newname, newvalue)
{
  if (arg >= ARGC) {
    echo("usage: es # [name] [value]");
    return;
  }
  entry = ARGV[arg++];
  newname = ARGV[arg++];
  newvalue = get_value(arg);
  add_name_value(entry, newname, newvalue);
}

function value(arg,  entry, newvalue)
{
  if (arg >= ARGC) {
    echo("usage: ev # [value]");
    return;
  }
  entry = ARGV[arg++];
  newvalue = get_value(arg);
  add_name_value(entry, enames[entry], newvalue);
}

function name(arg,  entry, newname)
{
  if (arg >= ARGC) {
    echo("usage: en # [name]");
    return;
  }
  entry = ARGV[arg++];
  newname = ARGV[arg++];
  add_name_value(entry, newname, evalues[entry]);
}

function change(arg,  entry, name, newvalue)
{
  if (argc >= ARGC) {
    echo("usage ec name [value]");
    return;
  }
  name = ARGV[arg++];
  newvalue = get_value(arg);
  for (entry=0; entry<emax; entry++) {
    if (name == enames[entry]) {
      add_name_value(entry, name, newvalue);
      return;
    }
  }
  echo("name " name " not found.");
}

function ls(arg,  i, proj, s, t)
{
  proj = ARGV[arg++]
  if (proj && proj != eproj) {
    eproj = proj;
    emax = read_project(eproj, evalues, enames);
  }
  echo(sprintf(YL "%-65s" NO "$name", eproj ":"));
  for(i=0; i<emax; i++) {
    s = evalues[i];
    if (length(s) > 60) {
      t = sprintf(CY "%2d" NO ": %-56s " RD "... " NO, i, substr(s, 1, 56));
    } else {
      t = sprintf(CY "%2d" NO ": %-60s ", i, s);
    }
    t = t sprintf("%-11s :" CY "%d" NO, (enames[i] ? "$" enames[i] : ""), i);
    echo(t)
  }
}

function echoenv(flags, proj, n, names, values,  fmt)
{
  fmt = flags["c"] ? CY "$%s" NO ",%s," GR"%s" NO "" : "$%s,%s,%s";
  for (i=0; i<n; i++) {
    if (!values[i]) {
      continue;
    }
    if (eproj == proj && (flags["A"] || flags["a"])) {
      echo(sprintf(fmt, "e" i, evalues[i], proj));
    }
    if (flags["A"]) {
      echo(sprintf(fmt, proj "_e" i, values[i], rojs));
    }
    if (!names[i]) {
      continue;
    }
    echo(sprintf(fmt, names[i], values[i], proj));
    if (flags["A"]) {
      echo(sprintf(fmt, proj "_" names[i], values[i], proj));
    }
  }
}

function env(arg,  projs, proj, i, j, n, names, values, flags, args)
{
  getopt(arg, "aAc", flags, args);
  projects_list(projs);
  for (j in projs) {
    n = read_project(projs[j], values, names);
    if (eproj == projs[j] || flags["A"] || flags["a"]) {
      echoenv(flags, projs[j], n, names, values);
    }
  }
}

function exchange(arg,  from, to, tmpvalue, tmpname)
{
  if (arg + 1 >= ARGC) {
    echo("usage: ex # #");
    return;
  }
  from = ARGV[arg++];
  to = ARGV[arg++];
  if (from >= emax && to >= emax) {
    echo("from (" from ") and to (" to ") both > max (" emax ") slots")
    return;
  }

  echo("exchange " from " " to ";");
  if (from < emax) {
    delete_environment(from);
  }
  if (to < emax) {
    delete_environment(to);
  }
  tmpvalue = evalues[from];
  tmpname = enames[from];
  evalues[from] = evalues[to];
  enames[from] = enames[to];
  evalues[to] = tmpvalue;
  enames[to] = tmpname;
  add_environment(from);
  add_environment(to);
  if (from >= emax) {
    emax = from + 1;
  }
  if (to >= emax) {
    emax = to + 1;
  }
  write_project(eproj, evalues, enames, emax);
}

function help(arg)
{
  echo(CY "ep " YL "[-t] [project]" NO ":");
  echo("\tdisplay projects, if " YL "project " NO \
  	" specified, set it to current");
  echo("\t(-t select project only in current shell)");
  echo(CY "erp " NO  YL "project" NO ":");
  echo("\tremove " YL "project " NO "(if current, default selected)");
  echo(CY "eep " NO  YL "[project]" NO ":");
  echo("\tedit " YL "project " NO "and resync (default current)");
  echo(CY "es " NO YL "0-# [name] [value]" NO ":");
  echo("\tmake slot " YL "# " NO "with " YL "name " NO "and " \
  	YL "value " NO "(empty name & value clears)");
  echo(CY "ev " NO YL "0-# [value]" NO ":");
  echo("\tstore " YL "value " NO "to slot " YL "0-# " NO \
  	"(empty value clears)");
  echo(CY "en " NO YL "0-# [name]" NO ":");
  echo("\tmake env variable " YL "name " NO "point to slot " YL "#" NO \
  	" (empty name clears)");
  echo(CY "ec " NO YL "name [value]" NO ":");
  echo("\tchange project variable " YL "name " NO "to " YL "value " \
	NO " (empty value clears)");
  echo(CY "el " NO YL "[project]" NO ":");
  echo("\tlist all slots titles in " YL "project " NO "(default current)");
  echo(CY "em " NO YL "-[Aac]" NO ":");
  echo("\tlist name,value,proj (-a=names,-A=names & proj_e<var>,-c=color)");
  echo(CY "ex " NO YL "from to" NO ":");
  echo("\texchange slots " YL "from " NO "and " YL "to" NO "");
  echo(CY "ei" NO ":\n\t(re)initialize environment and commands");
  echo(CY "eq" NO ":\n\tremove env and commands");
  echo(CY "eh" NO ":\n\tprint this help message");
}

function init(arg, useenv,  i, projs)
{
  aliaseval("eh", "help");
  aliaseval("el", "ls");
  aliaseval("em", "env");
  aliaseval("ei", "reinit");
  aliaseval("eq", "quit");
  aliaseval("ep", "projects");
  aliaseval("erp", "rm");
  aliaseval("eep", "edit");
  aliaseval("es", "store");
  aliaseval("en", "name");
  aliaseval("ev", "value");
  aliaseval("ec", "change");
  aliaseval("ex", "exchange");

  get_current_project(useenv);
  emax = read_project(eproj, evalues, enames);

  setenv("EHOME", ehome);
  setenv("EPROJECT", eproj);

  i = ehome "/" eproj ".project"
  if ((getline < i) < 0) {
    echo("created " i);
    select_project(eproj);
  }
  close(i);

  projects_list(projs)
  setenv("EPROJECTS", join(projs, ","));
  for(i in projs) {
    add_project_environment(projs[i]);
  }

  add_current_project();

  if (iscsh(shell())) {
    unsetenv("e");
  }
}

function quit(arg,  i, n, projs)
{
  for (i in ecommands) {
    unalias(ecommands[i])
  }

  n = split(ENVIRON["EPROJECTS"], projs, ",");
  for (i=1; i<=n; i++) {
    delete_project_environment(projs[i]);
    unsetenv("EPROJECTS_" projs[i]);
  }

  unsetenv("EPROJECTS")
  unsetenv("EPROJECT")
  unsetenv("EHOME")
  printf("\n");
}

function add_evar(vars, i, proj, entry, name)
{
  if (proj == eproj) {
    vars[i++] = "e" entry;
  }
  vars[i++] = proj "_e" entry;
  if (proj != eproj && isinit(name)) {
    return i;
  }
  if (name) {
    vars[i++] = name;
    vars[i++] = proj "_" name;
  }
  return i;
}

function write_eprojects(  projs, proj, i, j, k, n, names, values, vars)
{
  projects_list(projs);
  for (proj in projs) {
    n = read_project(projs[proj], values, names);
    j=0;
    delete vars;
    for(i=0; i<n; i++) {
      j = add_evar(vars, j, projs[proj], i, names[i]);
    }
    setenv("EPROJECTS_" projs[proj], join(vars,","));
  }
}

BEGIN {
  NO="\x1b[0;0m"
  BR="\x1b[0;01m"
  RD="\x1b[31;01m"
  GR="\x1b[32;01m"
  YL="\x1b[33;01m"
  BL="\x1b[34;01m"
  MG="\x1b[35;01m"
  CY="\x1b[36;01m"

  DONT_USE_ENV = 0;
  USE_ENV = 1;

  split("eh el em ei eq ep erp eep es en ev ex", ecommands) 
  
  ehome = ENVIRON["EHOME"];
  if (!ehome) {
    ehome = ENVIRON["HOME"] "/.e";
  }
  set_formats();

  get_current_project(USE_ENV);
  emax = read_project(eproj, evalues, enames);

  arg = 1;
  cmd = ARGV[arg++];
  if (cmd == "help") {
    help(arg);
    exit(0);
  } else if(cmd == "reinit") {
    quit(arg)
    init(arg, USE_ENV);
  } else if(cmd == "init") {
    init(arg, DONT_USE_ENV);
  } else if(cmd == "quit") {
    quit(arg);
    exit(0);
  } else if(cmd == "projects") {
    projects(arg);
    exit(0);
  } else if (cmd == "rm") {
    rm(arg);
  } else if (cmd == "edit") {
    edit(arg);
    exit(0);
  } else if(cmd == "store") {
    store(arg);
  } else if(cmd == "name") {
    name(arg);
  } else if (cmd == "value") {
    value(arg);
  } else if (cmd == "change") {
    change(arg);
  } else if(cmd == "ls") {
    ls(arg);
    exit(1);
  } else if(cmd == "env") {
    env(arg);
    exit(0);
  } else if(cmd == "exchange") {
    exchange(arg);
  } else {
    printf("invalid command '%s'\n", cmd);
    exit(0);
  }
  write_eprojects();
}

# vim: sw=2:

