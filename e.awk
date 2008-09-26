#!/bin/awk -f

# globals:
#  ehome - environment variable $EHOST
#  ehost - `hostname -s`
#  eproj - <ehome>/<ehost>-currentproject
#  eprojfile - <ehome>/<eproj>.project

function isbourne(shell)
{
  return shell == "zsh" || shell == "bash" || shell == "sh";
}

function iscsh(shell)
{
  return shell == "csh";
}

function setformats(shell)
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

function getcurrentproject(  file, proj)
{
  file = ehome "/" ehost "-currentproject";
  if ((getline proj < file) < 0) {
    proj = "default"
  }
  close(file);
  return proj
}

function setcurrentproject(proj,  file)
{
  file = ehome "/" ehost "-currentproject";
  printf("%s\n", proj) > file;
  close(file);
}

function readproj(values, names,  i)
{
  FS = ",";
  emax = 0;
  while (getline < eprojfile > 0) {
    values[emax] = $1;
    names[emax++] = $2;
  }
  close(eprojfile);
}

function writeproj(values, names,  i)
{
  for(i=0;i<emax;i++) {
    printf("%s,%s\n", values[i], names[i]) > eprojfile;
  }
  close(eprojfile);
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
  printf(CY "eq" NO ":                  %s\n",
      "remove env and alises");
  printf(CY "eh" NO ":                  %s\n",
      "print this help message");
}

function addentry(entry,  name, value, aliasecho)
{
  name = enames[entry]
  value = evalues[entry]

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

function deleteentry(entry,  name, value)
{
  name = enames[entry]
  value = evalues[entry]

  unalias("es" entry);
  unalias("en" entry);

  unalias("e" entry);
  if (name) {
    unalias("e" name);
    unsetenv(name);
  }
  if (entry == 0) {
    unalias("e");
  }
}

function listprojs(  projnm, leader)
{
  FS="/";
  while (sprintf("ls %s/*.project", ehome) |getline) {
    projnm=$NF
    gsub(".project", "", projnm);
    if (eproj == projnm) {
      leader = ">" YL;
    } else {
      leader = " " CY;
    }
    echo(leader projnm NO);
  }
}

function createproj(proj, mx,  i)
{
  mx = mx;
  if (mx == 0) {
    mx = EMAXDEFAULT;
  }
  # take all enames and unset them
  for(i=0; i<emax; i++) {
    deleteentry(i);
  }
  delete evalues;
  delete enames;
  setcurrentproject(proj);
  eproj = proj
  eprojfile = ehome "/" eproj ".project";
  readproj(evalues, enames);
  if (emax == 0) {
    emax = mx;
    writeproj(evalue, enames);
  }
  for(i=0; i<emax; i++) {
    addentry(i);
  }
}

function resizeproj(mx)
{
  if (mx < emax) {
    for (;emax > mx; emax--) {
      if (evalues[emax-1]) {
        break;
      }
      deleteentry(emax-1)
      delete evalues[emax-1];
      delete enames[emax-1];
    }
  } else {
    for (;emax < mx; emax++) {
      evalues[emax] = "";
      enames[emax] = "";
      addentry(emax)
    }
  }
  writeproj(evalues, enames);
}

function project(arg,   proj, projnm)
{
  proj = ARGV[arg++];
  if (proj) {
    mx = ARGV[arg++];
    if (proj != eproj) {
      createproj(proj, mx)
    } else if (mx != 0 && emax != mx) {
      resizeproj(mx);
    }
    writeproj(evalues, enames);
  }
  listprojs();
}

function rmproj(arg,  name)
{
  name = ARGV[arg++];
  if (name == eproj) {
    echo(sprintf("cannot remove current project '%s'", name));
  } else {
    if (system(sprintf("/bin/mv %s/%s.oldproject",ehome,name))) {
      echo(sprintf("cannot remove project '%s'", name));
    }
    listprojs();
  }
}

function store(arg,  entry, value)
{
  entry = ARGV[arg++];
  value = ARGV[arg++];
  for (; arg<ARGC; arg++) {
    value = value " " ARGV[arg];
  }
  deleteentry(entry);
  evalues[entry] = value;
  if (value) {
    addentry(entry);
  }
  writeproj(evalues, enames);
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

function removename(name,  i)
{
  for (i=0; i<emax; i++) {
    if (enames[i] == name) {
      deleteentry(i);
      enames[i] = "";
      addentry(i);
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
  removename(newname);
  deleteentry(entry);
  enames[entry] = newname;
  addentry(entry);
  writeproj(evalues, enames);
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
    readproj(evalues, enames);
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
  deleteentry(from);
  deleteentry(to);
  tmpvalue = evalues[from];
  tmpname = enames[from];
  evalues[from] = evalues[to];
  enames[from] = enames[to];
  evalues[to] = tmpvalue;
  enames[to] = tmpname;
  addentry(from);
  addentry(to);
  writeproj(evalues, enames);
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
    deleteentry(i);
    evalues[i] = newvalues[i];
    enames[i] = newnames[i];
    addentry(i);
  }
  writeproj(evalues, enames);
}

function init(arg,  i)
{
  eshell = ARGV[arg++];
  setformats(eshell);
  setenv("ESHELL", eshell);

  aliaseawk("eh", "help");
  aliaseawk("el", "list");
  aliaseawk("em", "mapping");
  aliaseval("ep", "proj");
  aliaseval("eq", "quit " shell);
  aliaseval("erp", "rmproj");
  aliaseval("ex", "exchange");
  aliaseval("eu", "rotate up");
  aliaseval("ew", "rotate down");
  aliaseval("ec", "clear");
  alias("es", "es0");
  alias("en", "en0");

  for(i=0; i<emax; i++) {
    addentry(i);
  }

  if (iscsh(shell)) {
    unsetenv("x");
  }
}

function quit(arg,  shell, i, efmt)
{
  shell = ARGV[arg++];
  for (command in ecommands) {
    unalias(ecommands[command])
  }
  for (i=0; i<emax; i++) {
    deleteentry(i);
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
  split("eh el em eq erp ep ex eu ed ec es en", ecommands) 
  ehome = ENVIRON["EHOME"];
  if (!ehome) {
    ehome = ENVIRON["HOME"] "/.e";
  }
  eshell = ENVIRON["ESHELL"];
  setformats(eshell);
  "hostname -s"|getline ehost; 
  emax=EMAXDEFAULT;
  eproj = getcurrentproject();
  eprojfile = ehome "/" eproj ".project";
  if ((getline < eprojfile) < 0) {
    createproj(eproj, EMAXDEFAULT);
  }
  close(eprojfile);
  readproj(evalues, enames);
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
