#!/bin/awk -f

# globals:
#  ehome - environment variable $EHOST
#  ehost - `hostname -s`
#  eproj - <ehome>/<ehost>-currentproject
#  eprojfile - <ehome>/<eproj>.project
#  evalues - environment values
#  enames - environment names
#  emax - number of entries

function get_current_project(home, host,  file, proj)
{
  file = home "/" host "-currentproject";
  if ((getline proj < file) < 0) {
    proj = "default"
  }
  close(file);
  return proj
}

function set_current_project(home, host, proj,  file)
{
  file = home "/" host "-currentproject";
  printf("%s\n", proj) > file;
  close(file);
}

function read_project(projfile, values, names,  i)
{
  FS = ",";
  i = 0;
  while (getline < projfile > 0) {
    values[i] = $1;
    names[i++] = $2;
  }
  close(eprojfile);
  return i
}

function write_project(projfile, values, names,  i)
{
  for(i=0;i<emax;i++) {
    printf("%s,%s\n", values[i], names[i]) > projfile;
  }
  close(eprojfile);
}

function projects_list(projs,  projnm, i)
{
  FS="/";
  i = 0
  while (sprintf("ls %s/*.project", ehome) |getline) {
    projnm=$NF
    gsub(".project", "", projnm);
    projs[i++] = projnm;
  }
}

function hostname(  host)
{
  "hostname -s"|getline host; 
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

function set_formats(shell)
{
  if (isbourne(shell)) {
    esetenvfmt = "export %s='%s'\n";
    eunsetenvfmt = "unset %s\n";
    ealiasfmt = "%s() {\n  %s \n}\n";
    eunaliasfmt = "unset -f %s\n";;
    ealiasechofmt = "echo \"%s $*\"; eval \"%s $*\"";
  } else if (iscsh(shell)) {
    esetenvfmt = "setenv %s \"%s\";";
    eunsetenvfmt = "unsetenv %s;";
    ealiasfmt = "alias %s \"%s\";";
    eunaliasfmt = "unalias %s;";
    ealiasechofmt = "echo \"%s \\!\\*\"; eval \"%s \\!\\*\"";
  }
}

function echo(s)
{
  printf("echo -n \"%s\";echo;", s);
}

function setenv(name, value)
{
  printf(esetenvfmt, name, value);
}

function unsetenv(name)
{
  printf(eunsetenvfmt, name);
}

function aliaseval(name, value)
{
  if (isbourne(eshell)) {
    printf("%s() {\n  eval \"$(%s/e.awk %s $*)\"\n}\n",
	   name, ehome, value);
  } else if (iscsh(eshell)) {
    printf("set x=(eval \\\"\\`%s/e.awk %s \\!\\*\\`\\\");alias %s \"$x\";",
	   ehome, value, name);
  }
}

function alias(name, value)
{
  printf(ealiasfmt, name, value);
}

function aliaseawk(name, value)
{
  if (isbourne(eshell)) {
    alias(name, sprintf("%s/e.awk %s $*", ehome, value));
  } else if (iscsh(eshell)) {
    alias(name, sprintf("%s/e.awk %s \\!*", ehome, value));
  }
}

function unalias(name)
{
  printf(eunaliasfmt, name);
}

function add_environment(entry, name, value, aliasecho)
{
  aliaseval("es" entry, "store " entry);
  aliaseval("en" entry, "name " entry);
  aliaseval("ev" entry, "value " entry);

  setenv("e" entry, value);
  setenv("e" eproj "_e" entry, value);
  alias("e" entry, sprintf(ealiasechofmt, value, value));
  if (entry == 0) {
    alias("e", sprintf(ealiasechofmt, value, value));
  }
  if (name != "") {
    setenv(name, value);
    setenv("e" eproj "_" name, value);
    alias(name, sprintf(ealiasechofmt, value, value));
  }
}

function delete_environment(entry, name, value)
{
  unalias("es" entry);
  unalias("en" entry);
  unalias("ev" entry);

  unalias("e" entry);
  unsetenv("e" entry);
  unsetenv("e" eproj "_e" entry);
  if (name) {
    unalias(name);
    unsetenv("e" name);
    unsetenv("e" eproj "_e" entry);
  }
}

function add_project_environment(proj,  projfile, names, values, mx, i)
{
  projfile = ehome "/" proj ".project";
  mx = read_project(projfile, values, names);
  for (i=0; i<mx; i++) {
    setenv("e" proj "_e" i, values[i]);
    if (names[i]) {
      setenv("e" proj "_" names[i], values[i]);
    }
  }
}

function delete_project_environment(proj,  projfile, names, values, mx, i)
{
  projfile = ehome "/" proj ".project";
  mx = read_project(projfile, values, names);
  for (i=0; i<mx; i++) {
    unsetenv("e" proj "_e" i);
    if (names[i]) {
      unsetenv("e" proj "_" names[i]);
    }
  }
}

function list_projects(  projnm, leader, projs, i)
{
  projects_list(projs); 
  for (i in projs) {
    projnm=projs[i]
    if (eproj == projnm) {
      leader = ">" YL;
    } else {
      leader = " " CY;
    }
    echo(leader projnm NO);
  }
}

function create_project(proj, mx,  i)
{
  mx = mx;
  if (mx == 0) {
    mx = EMAXDEFAULT;
  }
  # take all enames and unset them
  for(i=0; i<emax; i++) {
    delete_environment(i, enames[i], evalues[i]);
  }
  delete evalues;
  delete enames;
  set_current_project(ehome, ehost, proj);
  eproj = proj
  eprojfile = ehome "/" eproj ".project";
  emax = read_project(eprojfile, evalues, enames);
  if (emax == 0) {
    emax = mx;
    write_project(eprojfile, evalue, enames);
  }
  for(i=0; i<emax; i++) {
    add_environment(i, enames[i], evalues[i]);
  }
}

function resize_project(mx)
{
  if (mx < emax) {
    for (;emax > mx; emax--) {
      if (evalues[emax-1]) {
        break;
      }
      delete_environment(emax-1, enames[emax-1], evalues[emax-1])
      delete evalues[emax-1];
      delete enames[emax-1];
    }
  } else {
    for (;emax < mx; emax++) {
      evalues[emax] = "";
      enames[emax] = "";
      add_environment(emax, enames[emax], evalues[emax])
    }
  }
  write_project(eprojfile, evalues, enames);
}

function project(arg,   proj, projnm)
{
  proj = ARGV[arg++];
  if (proj) {
    mx = ARGV[arg++];
    if (proj != eproj) {
      create_project(proj, mx)
    } else if (mx != 0 && emax != mx) {
      resize_project(mx);
    }
    write_project(eprojfile, evalues, enames);
  }
  list_projects();
}

function rmproj(arg,  name)
{
  name = ARGV[arg++];
  if (name == eproj) {
    echo(sprintf("cannot remove current project '%s'", name));
  } else {
    delete_project_environment(name);
    cmd = sprintf("/bin/mv %s/%s.project %s/%s.oldproject",
	  ehome, name, ehome, name);
    if (system(cmd)) {
      echo(sprintf("cannot remove project '%s'", name));
    }
    list_projects();
  }
}

function add_value(entry, value)
{
  if (value && enames[entry] == value) {
    echo(sprintf("invalid value '%s' cannot be same as name", value));
    return;
  }
  delete_environment(entry, enames[entry], evalues[entry]);
  evalues[entry] = value;
  add_environment(entry, enames[entry], evalues[entry]);
  write_project(eprojfile, evalues, enames);
  printf("\n");
}

function store(arg,  entry, value)
{
  entry = ARGV[arg++];
  value = ARGV[arg++];
  for (; arg<ARGC; arg++) {
    value = value " " ARGV[arg];
  }
  add_value(entry, value);
}

function isreserved(value)
{
  for (i in ecommands) {
    command = ecommands[i]
    if (command == value) {
      return command;
    }
  }
  split("e es en ev", leaders)
  for (i=0; i<emax; i++) {
    for (l in leaders) {
      if (leaders[l] i == value) {
	return leaders[l] i;
      }
    }
  }
  return "";
}

function remove_name(name,  i)
{
  for (i=0; i<emax; i++) {
    if (enames[i] == name) {
      delete_environment(i, enames[entry], evalues[entry]);
      enames[i] = "";
      add_environment(i, enames[i], evalues[i]);
    }
  }
}

function add_name(entry, name,  reserved)
{
  # validate name
  if (name && evalues[entry] == name) {
    echo(sprintf("invalid name '%s' cannot be same as value", name));
    return;
  }
  reserved = isreserved(name);
  if (reserved) {
    echo(sprintf("invalid name '%s' for entry %d is reserved",
	  reserved, entry));
    return
  }
  remove_name(name);
  delete_environment(entry, enames[entry], evalues[entry]);
  enames[entry] = name;
  add_environment(entry, enames[entry], evalues[entry]);
  write_project(eprojfile, evalues, enames);
  printf("\n");
}

function name(arg,  entry, newname, i)
{
  entry = ARGV[arg++];
  newname = ARGV[arg++];
  add_name(entry, newname);
}

function value(arg,  entry, name, val)
{
  entry = ARGV[arg++];
  name = ARGV[arg++];
  val = ARGV[arg++];
  for (; arg<ARGC; arg++) {
    val = val " " ARGV[arg];
  }
  add_value(entry, val);
  add_name(entry, name);
}

function eval(arg,  entry, e, i)
{
  entry = ARGV[arg++];
  e = evalues[entry];
  for (; arg < ARGC; arg++) {
    e = e " " ARGV[arg];
  }
  printf("%s\n", e)
}

function list(arg,  i, proj)
{
  proj = ARGV[arg++]
  if (proj && proj != eproj) {
    eproj = proj;
    eprojfile = ehome "/" proj ".project";
    emax = read_project(eprojfile, evalues, enames);
  }
  printf(YL eproj NO ":\n");
  for(i=0; i<emax; i++) {
    printf(CY "%2d" NO ": %-60s ", i, evalues[i]);
    if (enames[i]) {
      printf("(" CY "$%s" NO ")", enames[i]);
    } else {
      printf("  - " CY "%d" NO " -", i);
    }
    printf("\n");
  }
}

function mapping(arg,  i)
{
  #rc = system("tty >/dev/null")
  #if (rc) {
  #  fmt = "$%s:%s\n";
  #} else {
  #  fmt = CY "$%s" NO ":%s\n";
  #}
  fmt = "$%s,%s\n";
  for(i=0;i<emax;i++) {
    if (enames[i]) {
      printf(fmt, enames[i], evalues[i]);
    }
  }
}

function exchange(arg,  from, to, tmpvalue, tmpname)
{
  from = ARGV[arg++];
  to = ARGV[arg++];

  printf("echo exchange %d %d;", from, to);
  delete_environment(from, enames[to], evalues[from]);
  delete_environment(to, enames[to], evalues[from]);
  tmpvalue = evalues[from];
  tmpname = enames[from];
  evalues[from] = evalues[to];
  enames[from] = enames[to];
  evalues[to] = tmpvalue;
  enames[to] = tmpname;
  add_environment(from, enames[from], evalues[from]);
  add_environment(to, enames[to], evalues[to]);
  write_project(eprojfile, evalues, enames);
}

function rotate(arg,  direction, positions, start, new, newvalues, newnames)
{
  direction = ARGV[arg++];
  positions = ARGV[arg++];
  printf("echo rotate %s %d;", direction, positions);
  if (direction == "up") {
    start = positions;
  } else if (direction == "down") {
    start = emax - positions;
  }
  for(i=0; i<emax; i++) {
    new = (start+i)%emax;
    newvalues[i] = evalues[new];
    newnames[i] = enames[new];
  }
  for(i=0; i<emax; i++) {
    delete_environment(i, enames[i], evalues[i]);
    evalues[i] = newvalues[i];
    enames[i] = newnames[i];
    add_environment(i, enames[i], evalues[i]);
  }
  write_project(eprojfile, evalues, enames);
}

function help(arg)
{
  printf(CY "ep"NO" ["GR"proj"NO" ["GR"nslots"NO"]]:  %s\n",
      "display proj(s) or set/create/resize proj with nslots");
  printf(CY "erp" NO " " GR "<proj>" NO ":          %s\n",
      "remove proj (cannot be current)");
  printf(CY "es" NO "," CY "es" NO "["GR"0-#"NO"] "GR"value"NO":    %s\n",
      "store value to slot 0-# (es=es0) (empty clears)");
  printf(CY "en" NO "," CY "en" NO "["GR"0-#"NO"] "GR"name"NO":     %s\n",
      "make environment variable name point to slot");
  printf(CY "ev" NO "," CY "ev" NO "["GR"0-#"NO"] "GR"name val"NO": %s\n",
      "make slot with name and value");
  printf(CY "e" NO "," CY "e" NO "["GR"0-#"NO"] ["GR"args"NO"]:     %s\n",
      "evaluate/execute slot value with args (e=e0)");
  printf(CY "el" NO ":                  %s\n",
      "list all slots titles by current proj");
  printf(CY "em" NO ":                  %s\n",
      "list env to dir mapping of current proj");
  printf(CY "ex" NO " " GR "from to" NO ":          %s\n",
      "exchange slots from and to");
  printf(CY "eu" NO " [" GR "num" NO "]:            %s\n",
      "rotate slots up 1 or num positions");
  printf(CY "ew" NO " [" GR "num" NO "]:            %s\n",
      "rotate slots up 1 or num positions");
  printf(CY "ei" NO ":                  %s\n",
      "(re)initialize env and alises");
  printf(CY "eq" NO ":                  %s\n",
      "remove env and alises");
  printf(CY "eh" NO ":                  %s\n",
      "print this help message");
}

function init(arg,  i, projs)
{
  eshell = ARGV[arg++];
  set_formats(eshell);
  setenv("ESHELL", eshell);

  aliaseawk("eh", "help");
  aliaseawk("el", "list");
  aliaseawk("em", "mapping");
  aliaseval("ei", "init " eshell);
  aliaseval("eq", "quit " eshell);
  aliaseval("ep", "proj");
  aliaseval("erp", "rmproj");
  aliaseval("ex", "exchange");
  aliaseval("eu", "rotate up");
  aliaseval("ew", "rotate down");
  aliaseval("ec", "clear");
  alias("es", "es0 $*");
  alias("en", "en0 $*");
  alias("ev", "ev0 $*");

  projects_list(projs)
  for(i in projs) {
    add_project_environment(projs[i]);
  }

  for(i=0; i<emax; i++) {
    add_environment(i, enames[i], evalues[i]);
  }

  if (iscsh(shell)) {
    unsetenv("x");
  }
}

function quit(arg,  shell, i, projs)
{
  shell = ARGV[arg++];
  set_formats(shell);
  for (i in ecommands) {
    unalias(ecommands[i])
  }
  for (i=0; i<emax; i++) {
    delete_environment(i, enames[i], evalues[i]);
  }

  projects_list(projs)
  for(i in projs) {
    delete_project_environment(projs[i]);
  }

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

  EMAXDEFAULT=30
  split("eh el em ei eq ep erp ex eu ew es en e", ecommands) 
  ehome = ENVIRON["EHOME"];
  if (!ehome) {
    ehome = ENVIRON["HOME"] "/.e";
  }
  eshell = ENVIRON["ESHELL"];
  set_formats(eshell);
  ehost = hostname();
  emax=EMAXDEFAULT;
  eproj = get_current_project(ehome, ehost);
  eprojfile = ehome "/" eproj ".project";
  if ((getline < eprojfile) < 0) {
    create_project(eproj, EMAXDEFAULT);
  }
  close(eprojfile);
  emax = read_project(eprojfile, evalues, enames);
  arg=1;
  cmd = ARGV[arg++];
  if (cmd == "help") {
    help(arg);
  } else if(cmd == "init") {
    init(arg);
  } else if(cmd == "quit") {
    quit(arg);
  } else if(cmd == "proj") {
    project(arg);
  } else if (cmd == "rmproj") {
    rmproj(arg);
  } else if(cmd == "store") {
    store(arg);
  } else if(cmd == "name") {
    name(arg);
  } else if (cmd == "value") {
    value(arg);
  } else if(cmd == "eval") {
    eval(arg);
  } else if(cmd == "list") {
    list(arg);
  } else if(cmd == "mapping") {
    mapping(arg);
  } else if(cmd == "exchange") {
    exchange(arg);
  } else if(cmd == "rotate") {
    rotate(arg);
  } else {
    printf("invalid command '%s'\n", cmd);
  }
}

# vim: sw=2:
