#!/bin/awk -f

# globals:
#  ehome - environment variable $EHOME
#  eproj - <ehome>/<hostname>-currentproject
#  eprojfile - <ehome>/<eproj>.project
#  evalues - environment values
#  enames - environment names
#  emax - number of entries

function getopt_single(arg, flag, opts, flags,  o)
{
  for (o=1; o<=length(opts); o++) {
    if (substr(opts, o, 1) != flag) {
      continue;
    } 
    if (substr(opts, o+1, 1) == ":") {
      flags[flag] = ARGV[++arg];
    } else {
      flags[flag] = 1;
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

function hostname(  host)
{
  "hostname -s"|getline host; 
  close("hostname -s");
  return host
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

function set_formats(shell)
{
  eevalfmt = "eval \"%s\"";
  if (isbourne(shell)) {
    esetenvfmt = "export %s='%s'\n";
    eunsetenvfmt = "unset %s\n";
    ealiasfmt = "%s() {\n  %s \n}\n";
    eunaliasfmt = "unset -f %s\n";;
  } else if (iscsh(shell)) {
    esetenvfmt = "setenv %s \"%s\";";
    eunsetenvfmt = "unsetenv %s;";
    ealiasfmt = "alias %s '%s';";
    eunaliasfmt = "unalias %s;";
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
  if (isbourne(eshell)) {
    printf("%s() {\n  eval \"$(%s/e.awk %s $*)\"\n}\n",
	   name, ehome, value);
  } else if (iscsh(eshell)) {
    printf("set e=(eval \\\"\\`%s/e.awk %s \\\\!\\*\\`\\\");alias %s \"$e\";",
	   ehome, value, name);
  }
}

function alias(name, value)
{
  #echo(sprintf("alias %s %s", name, value));
  printf(ealiasfmt, name, value);
}

function unalias(name)
{
  #echo(sprintf("unalias %s %s", name));
  printf(eunaliasfmt, name);
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

function get_current_project(  file)
{
  file = ehome "/current-" hostname();
  if ((getline eproj < file) < 0) {
    eproj = "default"
    set_current_project(eproj);
  }
  close(file);
  eprojfile = ehome "/" eproj ".project";
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

function projects_list(projs,  projnm, i)
{
  FS="/";
  i = 0
  while (sprintf("ls %s/*.project", ehome) |getline) {
    projnm=$NF
    gsub("\\.project", "", projnm);
    projs[i++] = projnm;
  }
  return i;
}

function add_env(proj, entry, name, value)
{
  if (value) {
    setenv(proj "_e" entry, value);
    alias(proj "_e" entry, sprintf(eevalfmt, value));
  }
  if (name) {
    if (isreserved(name)) {
      echo(sprintf("%s slot %d is project %s reserved. no env created",
 		name, entry, eproj));
      return;
    }
    setenv(name, value)
    setenv(proj "_" name, value);
    alias(proj "_" name, value);
    if (name == "init" || name == "deinit") {
      if (proj != eproj) {
	return;
      }
    }
    alias(name, value);
  }
}

function delete_env(proj, entry, name, value)
{
  if (value) {
    unalias(proj "_e" entry);
  }
  unsetenv(proj "_e" entry);
  if (name) {
    unalias(name);
    unsetenv(proj "_" name);
    unsetenv(name);
  }
}

function add_environment(entry)
{
  setenv("e" entry, evalues[entry]);
  alias("e" entry, sprintf(eevalfmt, evalues[entry]));
  add_env(eproj, entry, enames[entry], evalues[entry]);
}

function delete_environment(entry)
{
  unalias("e" entry);
  unsetenv("e" entry);
  delete_env(eproj, entry, enames[entry], evalues[entry]);
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
  n = read_project(proj, values, names);
  for (i=0; i<n; i++) {
    delete_env(proj, i, names[i], values[i]);
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
      printf("%s;", evalues[i]);
    }
  }
}

function clear_current_project(  i)
{
  for(i=0; i<emax; i++) {
    if (enames[i] == "deinit") {
      printf("%s;", evalues[i]);
    }
  }

  for(i=0; i<emax; i++) {
    delete_environment(i);
  }

  add_project_environment(eproj);
}

function select_project(proj,  i, projfile)
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
  set_current_project(eproj);
}

function projects(arg,   proj, projnm, n)
{
  proj = ARGV[arg++];
  if (proj && !isidentifier(proj)) {
    echo(sprintf("invalid project name \"%s\"", proj));
    return;
  }
  if (proj && proj != eproj) {
    select_project(proj)
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
    echo(sprintf("cannot remove default project '%s'", proj));
    return;
  }
  if (proj == eproj) {
    select_project("default");
  }
  delete_project_environment(proj);
  cmd = sprintf("/bin/mv %s/%s.project %s/%s.oldproject",
	ehome, proj, ehome, proj);
  if (system(cmd)) {
    echo(sprintf("cannot rename project '%s'", proj));
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
  printf("%s %s;ei", ENVIRON["EDITOR"], ehome "/" proj ".project");
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
      echo(sprintf("invalid name '%s' cannot be same as value", newname));
      return;
    }
    if (isreserved(newname)) {
      echo(sprintf("invalid name '%s' for entry %d is reserved", newname, entry));
      return
    }
    if (!isidentifier(newname)) {
      echo(sprintf("invalid name %s", newname));
      return;
    }
  }
  echo(sprintf("slot %d \"%s\" \"%s\" to project %s",
  	entry, newname, newvalue, eproj));
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

function value(arg,  entry, newvalue)
{
  if (arg >= ARGC) {
    echo("usage: ev # [value]");
    return;
  }
  entry = ARGV[arg++];
  newvalue = ARGV[arg++];
  for (; arg<ARGC; arg++) {
    newvalue = newvalue " " ARGV[arg];
  }
  add_name_value(entry, enames[entry], newvalue);
}

function name(arg,  entry, newname, i)
{
  if (arg >= ARGC) {
    echo("usage: en # [name]");
    return;
  }
  entry = ARGV[arg++];
  newname = ARGV[arg++];
  add_name_value(entry, newname, evalues[entry]);
}

function store(arg,  entry, newname, newvalue)
{
  if (arg >= ARGC) {
    echo("usage: es # [name] [value]");
    return;
  }
  entry = ARGV[arg++];
  newname = ARGV[arg++];
  newvalue = ARGV[arg++];
  for (; arg<ARGC; arg++) {
    newvalue = newvalue " " ARGV[arg];
  }
  add_name_value(entry, newname, newvalue);
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
      t = sprintf(CY "%2d" NO ": %-56s " RD "..." NO, i, substr(s, 1, 56));
    } else {
      t = sprintf(CY "%2d" NO ": %-60s ", i, s);
    }
    if (enames[i]) {
      t = t sprintf("$%-10s", enames[i]);
    } else {
      t = t sprintf("%-11s", "");
    }
    t = t sprintf(" :" CY "%d" NO, i);
    echo(t)
  }
}

function env(arg,  projs, proj, i, j, n, names, values, flags, args)
{
  getopt(arg, "aAc", flags, args);
  if (flags["c"]) {
    fmt = CY "$%s" NO ",%s," GR"%s" NO "";
  } else {
    fmt = "$%s,%s,%s";
  }
  if (flags["A"] || flags["a"]) {
    projects_list(projs);
    for (j in projs) {
      if (projs[j] == eproj) {
	continue;
      }
      n = read_project(projs[j], values, names);
      for (i=0; i<n; i++) {
        if (!values[i]) {
	  continue;
	}
	if (flags["A"]) {
	  echo(sprintf(fmt, projs[j] "_e" i, values[i], projs[j]));
	}
	if (!names[i]) {
	  continue;
	}
	echo(sprintf(fmt, names[i], values[i], projs[j]));
	if (flags["A"]) {
	  echo(sprintf(fmt, projs[j] "_" names[i], values[i], projs[j]));
	}
      }
    }
  }
  for(i=0;i<emax;i++) {
    if (enames[i]) {
      echo(sprintf(fmt, enames[i], evalues[i], eproj));
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
    echo(sprintf("from (%d) and to (%d) both > max (%d) slots",
    	from, to, emax));
    return;
  }

  printf("echo exchange %d %d;", from, to);
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
  echo(sprintf(CY "ep " YL "[project]" NO ":"));
  echo(sprintf("\tdisplay projects, if " YL "project " NO \
  	" specified, set it to current"));
  echo(sprintf(CY "erp " NO  YL "project" NO ":"));
  echo(sprintf("\tremove " YL "project " NO "(if current, default selected)"));
  echo(sprintf(CY "eep " NO  YL "[project]" NO ":"));
  echo(sprintf("\tedit " YL "project " NO "and resync (default current)"));
  echo(sprintf(CY "ev " NO YL "0-# value" NO ":"));
  echo(sprintf("\tstore " YL "value " NO "to slot " YL "0-# " NO \
  	"(empty value clears)"));
  echo(sprintf(CY "en " NO YL "0-# name" NO ":"));
  echo(sprintf("\tmake env variable " YL "name " NO "point to slot " YL "#" NO \
  	" (empty name clears)"));
  echo(sprintf(CY "es " NO YL "0-# name value" NO ":"));
  echo(sprintf("\tmake slot " YL "# " NO "with " YL "name " NO "and " \
  	YL "value " NO "(empty name & value clears)"));
  echo(sprintf(CY "el " NO YL "[project]" NO ":"));
  echo(sprintf("\tlist all slots titles in " YL "project " NO "(default current)"));
  echo(sprintf(CY "em " NO YL "-[Aac]" NO ":"));
  echo(sprintf("\tlist name,value,proj (-a=names,-A=names & proj_e<var>,-c=color)"));
  echo(sprintf(CY "ex " NO YL "from to" NO ":"));
  echo(sprintf("\texchange slots " YL "from " NO "and " YL "to" NO ""));
  echo(sprintf(CY "ei" NO ":\n\t(re)initialize environment and alises"));
  echo(sprintf(CY "eq" NO ":\n\tremove env and alises"));
  echo(sprintf(CY "eh" NO ":\n\tprint this help message"));
}

function init(arg,  i, projs)
{
  eshell = ARGV[arg++];
  set_formats(eshell);
  setenv("ESHELL", eshell);
  setenv("EHOME", ehome);
  setenv("EPROJECT", eproj);

  if ((getline < eprojfile) < 0) {
    echo(sprintf("create %s\n", eprojfile));
    select_project(eproj);
  }
  close(eprojfile);

  projects_list(projs)
  for(i in projs) {
    add_project_environment(projs[i]);
  }

  aliaseval("eh", "help");
  aliaseval("el", "ls");
  aliaseval("em", "env");
  aliaseval("ei", "init " eshell);
  aliaseval("eq", "quit " eshell);
  aliaseval("ep", "projects");
  aliaseval("erp", "rm");
  aliaseval("eep", "edit");
  aliaseval("es", "store");
  aliaseval("en", "name");
  aliaseval("ev", "value");
  aliaseval("ex", "exchange");

  add_current_project()

  if (iscsh(shell)) {
    unsetenv("e");
  }
}

function quit(arg,  shell, i, projs)
{
  shell = ARGV[arg++];
  set_formats(shell);
  for (i in ecommands) {
    unalias(ecommands[i])
  }

  projects_list(projs)
  for(i in projs) {
    delete_project_environment(projs[i]);
  }

  unsetenv("EPROJECT")
  unsetenv("EHOME")
  unsetenv("ESHELL")
  printf("\n");
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

  split("eh el em ei eq ep erp eep es en ev ex", ecommands) 
  
  ehome = ENVIRON["EHOME"];
  if (!ehome) {
    ehome = ENVIRON["HOME"] "/.e";
  }
  eshell = ENVIRON["ESHELL"];
  set_formats(eshell);

  get_current_project();
  emax = read_project(eproj, evalues, enames);

  arg = 1;
  cmd = ARGV[arg++];
  if (cmd == "help") {
    help(arg);
  } else if(cmd == "init") {
    init(arg);
  } else if(cmd == "quit") {
    quit(arg);
  } else if(cmd == "projects") {
    projects(arg);
  } else if (cmd == "rm") {
    rm(arg);
  } else if (cmd == "edit") {
    edit(arg);
  } else if(cmd == "store") {
    store(arg);
  } else if(cmd == "name") {
    name(arg);
  } else if (cmd == "value") {
    value(arg);
  } else if(cmd == "ls") {
    ls(arg);
  } else if(cmd == "env") {
    env(arg);
  } else if(cmd == "exchange") {
    exchange(arg);
  } else {
    printf("invalid command '%s'\n", cmd);
  }
}

# vim: sw=2:

