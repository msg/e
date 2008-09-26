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
    eunaliasfmt = eunsetenvfmt;
  } else if (iscsh(shell)) {
    esetenvfmt = "setenv %s \"%s\";";
    eunsetenvfmt = "unsetenv %s;";
    ealiasfmt = "alias %s \"%s\";";
    eunaliasfmt = "unalias %s;";
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
    alias(name, sprintf("%s/e.awk %s \\!\\*", ehome, value));
  }
}

function unalias(name)
{
  printf(eunaliasfmt, name);
}

function add_environment(entry, name, value, aliasecho)
{
  aliasecho = sprintf("echo \"%s\"; eval \"%s\"", value, value);
  aliaseval("es" entry, "store " entry);
  aliaseval("en" entry, "name " entry);

  setenv("e" entry, value);
  alias("e" entry, aliasecho);
  if (entry == 0) {
    alias("e", aliasecho);
  }
  if (name != "") {
    setenv(name, value);
    alias("e" name, aliasecho);
  }
}

function delete_environment(entry, name, value)
{
  unalias("es" entry);
  unalias("en" entry);

  unalias("e" entry);
  if (name) {
    unalias("e" name);
    unsetenv("e" name);
  }
  if (entry == 0) {
    unalias("e");
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
    unsetenv("e" proj "_e" i, values[i]);
    if (names[i]) {
      unsetenv("e" proj "_" names[i], values[i]);
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
    if (system(sprintf("/bin/mv %s/%s.oldproject",ehome,name))) {
      echo(sprintf("cannot remove project '%s'", name));
    }
    list_projects();
  }
}

function store(arg,  entry, value)
{
  entry = ARGV[arg++];
  value = ARGV[arg++];
  for (; arg<ARGC; arg++) {
    value = value " " ARGV[arg];
  }
  delete_environment(entry, enames[entry], evalues[entry]);
  evalues[entry] = value;
  if (value) {
    add_environment(entry, evalues[entry], enames[entry]);
  }
  write_project(eprojfile, evalues, enames);
  printf("\n");
}

function isreserved(value)
{
  for (i in ecommands) {
    command = ecommands[i]
    if (command == "e" value) {
      return command;
    }
  }
  split("e es en", leaders)
  for (i=0; i<emax; i++) {
    for (l in leaders) {
      if (leaders[l] i == "e" value) {
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

function name(arg,  entry, newname, i)
{
  entry = ARGV[arg++];
  newname = ARGV[arg++];
  # validate name
  reserved = isreserved(newname);
  if (reserved) {
    echo(sprintf("invalid name '%s' for entry %d is reserved",
	  reserved, entry));
    return
  }
  remove_name(newname);
  delete_environment(entry, enames[entry], evalues[entry]);
  enames[entry] = newname;
  add_environment(entry, enames[entry], evalues[entry]);
  write_project(eprojfile, evalues, enames);
  printf("\n");
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
      "store value to entries 0-# (es=es0) (empty clears)");
  printf(CY "en" NO "," CY "en" NO "["GR"0-#"NO"] "GR"name"NO":     %s\n",
      "make environment variable name point to entry");
  printf(CY "e" NO "," CY "e" NO "["GR"0-#"NO"] ["GR"args"NO"]:     %s\n",
      "evaluate/execute entry with args (e=e0)");
  printf(CY "el" NO ":                  %s\n",
      "list all entries titles by current proj");
  printf(CY "em" NO ":                  %s\n",
      "list env to dir mapping of current proj");
  printf(CY "ex" NO " " GR "from to" NO ":          %s\n",
      "exchange entries from and to");
  printf(CY "eu" NO " [" GR "num" NO "]:            %s\n",
      "rotate entries up 1 or num positions");
  printf(CY "ed" NO " [" GR "num" NO "]:            %s\n",
      "rotate entries up 1 or num positions");
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
  aliaseval("ep", "proj");
  aliaseval("ei", "init " shell);
  aliaseval("eq", "quit " shell);
  aliaseval("erp", "rmproj");
  aliaseval("ex", "exchange");
  aliaseval("eu", "rotate up");
  aliaseval("ew", "rotate down");
  aliaseval("ec", "clear");
  alias("es", "es0");
  alias("en", "en0");

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
  for (command in ecommands) {
    unalias(ecommands[command])
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
  split("eh el em ei eq erp ep ex eu ed ec es en", ecommands) 
  ehome = ENVIRON["EHOME"];
  if (!ehome) {
    ehome = ENVIRON["HOME"] "/.e";
  }
  eshell = ENVIRON["ESHELL"];
  set_formats(eshell);
  "hostname -s"|getline ehost; 
  emax=EMAXDEFAULT;
  eproj = get_current_project(ehost, ehost);
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