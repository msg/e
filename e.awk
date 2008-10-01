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

function read_project(projfile, values, names,  i, j)
{
  delete values;
  delete names;
  FS = ",";
  i = 0;
  while ((getline < projfile) > 0) {
    values[i] = $1;
    for(j=2; j<NF; j++) {
      values[i] = values[i] "," $j;
    }
    names[i++] = $NF;
  }
  close(projfile);
  return i
}

function write_project(projfile, values, names,  i)
{
  for(i=0;i<emax;i++) {
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
    ealiasechofmt = "eval \"%s\"";
  } else if (iscsh(shell)) {
    esetenvfmt = "setenv %s \"%s\";";
    eunsetenvfmt = "unsetenv %s;";
    ealiasfmt = "alias %s '%s';";
    eunaliasfmt = "unalias %s;";
    ealiasechofmt = "eval \"%s\";";
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
    printf("set e=(eval \\\"\\`%s/e.awk %s \\\\!\\*\\`\\\");alias %s \"$e\";",
	   ehome, value, name);
  }
}

function alias(name, value)
{
  printf(ealiasfmt, name, value);
}

function alias_eawk(name, value)
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

function add_environment(entry, name, value)
{
  aliaseval("es" entry, "store " entry);
  aliaseval("en" entry, "name " entry);
  aliaseval("ev" entry, "value " entry);

  setenv("e" entry, value);
  if (value) {
    setenv("e" eproj "_e" entry, value);
  }
  alias("e" entry, sprintf(ealiasechofmt, value, value));
  if (entry == 0) {
    alias("e", sprintf(ealiasechofmt, value, value));
  }
  if (name) {
    setenv(name, value);
    setenv("e" eproj "_" name, value);
    alias(name, sprintf(ealiasechofmt, value, value));
  }
}

function delete_environment(entry, name)
{
  unalias("es" entry);
  unalias("en" entry);
  unalias("ev" entry);

  unalias("e" entry);
  unsetenv("e" entry);
  unsetenv("e" eproj "_e" entry);
  if (name) {
    unalias(name);
    unsetenv(name);
    unsetenv("e" proj "_" name);
  }
}

function add_project_environment(proj,  names, values, n, i)
{
  n = read_project(ehome "/" proj ".project", values, names);
  for (i=0; i<n; i++) {
    if (!values[i]) {
      continue;
    }
    setenv("e" proj "_e" i, values[i]);
    alias("e" proj "_e" i, sprintf(ealiasechofmt, values[i], values[i]));
    if (!names[i]) {
      continue;
    }
    setenv("e" proj "_" names[i], values[i]);
    alias("e" proj "_" names[i], sprintf(ealiasechofmt, values[i], values[i]));
    if (names[i] != "init" || names[i] != "deinit") {
      setenv(names[i], values[i]);
      alias(names[i], sprintf(ealiasechofmt, values[i], values[i]));
    }
  }
}

function delete_project_environment(proj,  names, values, n, i)
{
  n = read_project(ehome "/" proj ".project", values, names);
  for (i=0; i<n; i++) {
    unsetenv("e" proj "_e" i);
    if (names[i]) {
      unsetenv("e" proj "_" names[i]);
      unalias("e" proj "_" names[i]);
      unsetenv(names[i]);
      unalias(names[i]);
    }
  }
}

function list_projects(  proj, leader, projs, i, n, names, values)
{
  projects_list(projs); 
  for (i in projs) {
    proj = ehome "/" projs[i] ".project";
    n = read_project(proj, values, names);
    if (eproj == projs[i]) {
      leader = ">" YL;
    } else {
      leader = " " CY;
    }
    echo(leader projs[i] NO " " n);
  }
}

function clear_current_project(  i)
{
  for(i=0; i<emax; i++) {
    if (enames[i] == "deinit") {
      printf("%s;", evalues[i]);
    }
  }
  # take all enames and unset them
  for(i=0; i<emax; i++) {
    delete_environment(i, enames[i]);
  }
}

function select_project(proj, n,  i, projfile, values, names)
{
  if (n == 0) {
    n = EMAXDEFAULT;
  }
  clear_current_project();
  add_project_environment(eproj);
  set_current_project(ehome, ehost, proj);
  eproj = proj
  setenv("EPROJECT", eproj);
  proj = ehome "/" eproj
  projfile = proj ".project";
  if ((getline < sprintf("%s.oldproject", proj)) > 0) {
    system("mv " proj ".oldproject " projfile);
  }
  emax = read_project(projfile, values, names);
  if (emax == 0) {
    emax = n;
  }
  write_project(projfile, values, names);
  for(i=0; i<emax; i++) {
    add_environment(i, names[i], values[i]);
  }
  for(i=0; i<emax; i++) {
    if (names[i] == "init") {
      printf("%s;", values[i]);
    }
  }
}

function resize_project(n)
{
  if (n < emax) {
    for (;emax > n; emax--) {
      if (evalues[emax-1]) {
        break;
      }
      delete_environment(emax-1, enames[emax-1])
      delete evalues[emax-1];
      delete enames[emax-1];
    }
  } else {
    for (;emax < n; emax++) {
      evalues[emax] = "";
      enames[emax] = "";
      add_environment(emax, enames[emax], evalues[emax])
    }
  }
  write_project(eprojfile, evalues, enames);
}

function project(arg,   proj, projnm, n)
{
  proj = ARGV[arg++];
  if (proj) {
    n = ARGV[arg++];
    if (proj != eproj) {
      select_project(proj, n)
    } else if (n != 0 && emax != n) {
      resize_project(n);
    }
  }
  list_projects();
}

function rmproj(arg,  proj)
{
  proj = ARGV[arg++];
  if (proj == eproj) {
    echo(sprintf("cannot remove current project '%s'", proj));
    return;
  }
  delete_project_environment(proj);
  cmd = sprintf("/bin/mv %s/%s.project %s/%s.oldproject",
	ehome, proj, ehome, proj);
  if (system(cmd)) {
    echo(sprintf("cannot rename project '%s'", proj));
  }
  for (i=0; i<emax; i++) {
    add_environment(i, enames[i], evalues[i]);
  }
  list_projects();
}

function add_value(entry, value)
{
  if (value && enames[entry] == value) {
    echo(sprintf("invalid value '%s' cannot be same as name", value));
    return;
  }
  delete_environment(entry, enames[entry]);
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
      delete_environment(i, enames[entry]);
      enames[i] = "";
      add_environment(i, enames[i], evalues[i]);
    }
  }
}

function add_name(entry, newname,  reserved)
{
  # validate name
  if (newname && evalues[entry] == newname) {
    echo(sprintf("invalid name '%s' cannot be same as value", newname));
    return;
  }
  reserved = isreserved(newname);
  if (reserved) {
    echo(sprintf("invalid name '%s' for entry %d is reserved",
	  reserved, entry));
    return
  }
  remove_name(newname);
  enames[entry] = newname;
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

function value(arg,  entry, newname, val)
{
  entry = ARGV[arg++];
  newname = ARGV[arg++];
  val = ARGV[arg++];
  for (; arg<ARGC; arg++) {
    val = val " " ARGV[arg];
  }
  add_value(entry, val);
  add_name(entry, newname);
}

function eval(arg,  entry)
{
  entry = ARGV[arg++];
  printf("%s\n", evalues[entry]);
}

function evalrange(arg,  ranges, i)
{
  split(ARGV[arg++], ranges, "-");
  for (i=ranges[1]; i<= ranges[2]; i++) {
    echo(evalues[i]);
    printf("%s\n", evalues[i]);
  }
}

function list(arg,  i, proj, s)
{
  proj = ARGV[arg++]
  if (proj && proj != eproj) {
    eproj = proj;
    eprojfile = ehome "/" proj ".project";
    emax = read_project(eprojfile, evalues, enames);
  }
  printf(YL eproj NO ":\n");
  for(i=0; i<emax; i++) {
    s = evalues[i];
    if (length(s) > 60) {
      s = substr(s, 1, 56) RD " ..." NO;
    }
    printf(CY "%2d" NO ": %-60s ", i, s);
    if (enames[i]) {
      printf("(" CY "$%s" NO ")", enames[i]);
    } else {
      printf("  - " CY "%d" NO " -", i);
    }
    printf("\n");
  }
}

function mapping(arg,  projs, proj, i, j, n, names, values, all, color)
{
  #rc = system("tty >/dev/null")
  #if (rc) {
  #  fmt = "$%s:%s\n";
  #} else {
  #  fmt = CY "$%s" NO ":%s\n";
  #}
  all = 0;
  color = 0;
  for (;arg < ARGC; arg++) {
    if (ARGV[arg] == "-a") {
      all = 1;
    } else if(ARGV[arg] == "-c") {
      color = 1;
    }
  }
  if (color) {
    fmt = CY "$%s" NO ",'%s'," GR" %s" NO "\n";
  } else {
    fmt = "$%s,'%s',%s\n";
  }
  if (all) {
    projects_list(projs);
    for (j in projs) {
      if (projs[j] == eproj) {
	continue;
      }
      proj = ehome "/" projs[j] ".project";
      n = read_project(proj, values, names);
      for (i=0; i<n; i++) {
	if (names[i]) {
	  printf(fmt, names[i], values[i], projs[j]);
	}
      }
    }
  }
  for(i=0;i<emax;i++) {
    if (enames[i]) {
      printf(fmt, enames[i], evalues[i], eproj);
    }
  }
}

function exchange(arg,  from, to, tmpvalue, tmpname)
{
  from = ARGV[arg++];
  to = ARGV[arg++];

  printf("echo exchange %d %d;", from, to);
  delete_environment(from, enames[to]);
  delete_environment(to, enames[to]);
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
    delete_environment(i, enames[i]);
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
  printf(CY "erp" NO " " GR "proj" NO ":            %s\n",
      "remove proj (cannot be current)");
  printf(CY "es" NO "["GR"0-#"NO"] "GR"value"NO":       %s\n",
      "store value to slot 0-# (es=es0) (empty clears)");
  printf(CY "en" NO "["GR"0-#"NO"] "GR"name"NO":        %s\n",
      "make environment variable name point to slot");
  printf(CY "ev" NO "["GR"0-#"NO"] "GR"name val"NO":    %s\n",
      "make slot with name and value");
  printf(CY "e" NO "," CY "e" NO "["GR"0-#"NO"] ["GR"args"NO"]:     %s\n",
      "evaluate/execute slot value with args (e=e0)");
  printf(CY "er" NO " "GR"slot"NO"[_"GR"slot"NO"]*:     %s\n",
      "evaluate/execute each slot between '_' specified in order");
  printf(CY "el" NO " [" GR "proj" NO "]:           %s\n",
      "list all slots titles by current proj");
  printf(CY "em " NO "[" GR "-a" NO "]:             %s\n",
      "list env to dir mapping of current proj (-a=all vars)");
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
  setenv("EPROJECT", eproj);

  projects_list(projs)
  for(i in projs) {
    add_project_environment(projs[i]);
  }

  alias_eawk("eh", "help");
  alias_eawk("el", "list");
  alias_eawk("em", "mapping");
  aliaseval("ei", "init " eshell);
  aliaseval("eq", "quit " eshell);
  aliaseval("ep", "project");
  aliaseval("erp", "rmproj");
  aliaseval("er", "evalrange");
  aliaseval("ex", "exchange");
  aliaseval("eu", "rotate up");
  aliaseval("ew", "rotate down");

  for(i=0; i<emax; i++) {
    add_environment(i, enames[i], evalues[i]);
  }
  for(i=0; i<emax; i++) {
    if (enames[i] == "init") {
      printf("%s;", evalues[i]);
    }
  }

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
  split("eh el em ei eq ep erp ex eu ew er e", ecommands) 
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
    select_project(eproj, EMAXDEFAULT);
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
  } else if(cmd == "project") {
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
  } else if(cmd == "evalrange") {
    evalrange(arg);
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

