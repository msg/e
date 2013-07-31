#include <stdio.h>
#include <stdarg.h>
#include <limits.h>
#include <stdlib.h>
#include <stdarg.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "stringfuncs.h"
#include "path.h"

#include "e.h"

#define MAX_ARGS	1024
#define MAX_PROJECTS	1024
#define MAX_SLOTS	100

#define NO "\x1b[0;0m"
#define BR "\x1b[0;01m"
#define RD "\x1b[31;01m"
#define GR "\x1b[32;01m"
#define YL "\x1b[33;01m"
#define BL "\x1b[34;01m"
#define MG "\x1b[35;01m"
#define CY "\x1b[36;01m"

using std::pair;

// ---------------------------------------------------------------
// internal methods
// ---------------------------------------------------------------

string pop_arg(string_list *args)
{
	string s;
	if (args->size() > 0) {
		s = (*args)[0];
		args->erase(args->begin());
	}
	return s;
}

string hostname(void)
{
	char name[HOST_NAME_MAX];
	int rc = gethostname(name, HOST_NAME_MAX);
	if (rc < 0)
		return "";
	return name;
}

string get_flags(string_list *args)
{
	string flags;
	string_list::iterator sli = args->begin();
	while (sli != args->end()) {
		if ((*sli)[0] == '-') {
			flags += sli->substr(1);
			args->erase(sli);
		} else
			sli++;
	}
	return flags;
}

string environ_get(const string& name, const string& default_="")
{
	char *var = getenv(name.c_str());
	if (var == NULL)
		return default_;
	else
		return var;
}

bool is_dir(const string& path)
{
	struct stat st;
	int rc = stat(path.c_str(), &st);
	if (rc < 0)
		return false;
	return S_ISDIR(st.st_mode);
}

bool is_init_var(const string& name)
{
	return name == "init" || name == "deinit";
}

const char *ecommands[] = {
	"eh", "el", "em", "ei", "eq", "ep", "erp", "eep",
	"es", "en", "ev", "ec", "ex", NULL,
};

bool is_reserved(const string& s)
{
	for (int i = 0; ecommands[i]; i++) {
		if (s == ecommands[i])
			return true;;
	}
	for (int i = 0; i < MAX_SLOTS; i++) {
		char buf[10];
		sprintf(buf, "%d", i);
		if (s == "e" + string(buf))
			return true;
	}
	return false;
}

bool is_identifier(const string& s)
{
	char c = s[0];
	// "[A-Za-z_][A-Za-z0-9_]"
	if (!isalpha(c) && c != '_')
		return false;
	for (size_t i=1; i < s.length(); i++) {
		c = s[i];
		if (!isalnum(c) && c != '_')
			return false;
	}
	return true;
}

// ---------------------------------------------------------------
// Shell methods
// ---------------------------------------------------------------

void Shell::setenv(const string& name, const string& value)
{
	printf("export %s='%s'\n", name.c_str(), value.c_str());
}

void Shell::unsetenv(const string& name)
{
	printf("unset %s\n", name.c_str());
}

void Shell::alias(const string& name, const string& value)
{
	if (is_dir(value)) {
		printf("%s () {\n\tcd \"%s\"\n}\n", name.c_str(), value.c_str());
	} else
		printf("%s () {\n\t%s\n}\n", name.c_str(), value.c_str());
}

void Shell::unalias(const string& name)
{
	printf("typeset -f %s >/dev/null && unset -f %s\n",
			name.c_str(), name.c_str());
}

void Shell::eval_alias(const string& path,
		const string& name, const string& value)
{
	printf("%s() {\n  eval \"$(%s %s $*)\"\n}\n",
			name.c_str(), path.c_str(), value.c_str());
}

void Shell::setenv_alias(const string& name, const string& value)
{
	setenv(name, value);
	alias(name, value);
}

void Shell::unsetenv_alias(const string& name)
{
	unsetenv(name);
	unalias(name);
}

void Shell::exec_alias(const string& name)
{
	printf("%s;", name.c_str());
}

void Shell::echo(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	printf("echo '%s';\n", vstringf(fmt, ap).c_str());
}

// ---------------------------------------------------------------
// Slot methods
// ---------------------------------------------------------------
Slot::Slot(Project *project_, int slot_,
		const string& value_, const string& name_) :
	project(project_),
	slot(slot_),
	value(value_),
	name(name_)
{
}

string_list Slot::names(void)
{
	Project *current = project->e->current;
	string_list strings;
	string ename = stringf("e%d", slot);

	if (value == "")
		goto done;

	// if slot does not have a name, add <project>_e# to list
	if (name == "" && !(project->flags & no_global_e_vars))
		strings.push_back(project->name + "_" + ename);

	if (project == current && name == "" && !(project->flags & no_e_vars))
		strings.push_back(ename);

	if (is_reserved(name)) {
		string s;
		s = stringf("name %s is reserved in slot %d in project %s. "
			"no env/alias created.",
			name.c_str(), slot, project->name.c_str());
		project->e->shell->echo(s.c_str());
		goto done;
	}

	// if slot doesn't have a name, we're done.
	if (name == "")
		goto done;

	if (project == current || !(project->flags & no_global_vars))
		strings.push_back(project->name + "_" + name);

	// init type names are only added if project is current
	if (project != current && is_init_var(name))
		goto done;

	if (project == current || !(project->flags & no_project_vars))
		strings.push_back(name);
done:
	return strings;
}


void Slot::add_environment(void) {
	if (value == "")
		return;
	string_list names_ = names();
	sequence_for_each(string_list, namesi, names_) {
		project->e->shell->setenv_alias(*namesi, value);
	}
}

void Slot::delete_environment(void) {
	string_list names_ = names();
	sequence_for_each(string_list, namesi, names_) {
		project->e->shell->unsetenv_alias(*namesi);
	}
}

// ---------------------------------------------------------------
// Project methods
// ---------------------------------------------------------------

typedef pair<string, string> slot_entry;
typedef vector<slot_entry> slot_entries;

static string_list split_value_name(const string &line)
{
	string_list value_name;
	string::size_type comma = line.find_last_of(",");
	if (comma == line.npos) {
		value_name.push_back("");
		value_name.push_back("");
	} else {
		value_name.push_back(line.substr(0, comma));
		value_name.push_back(line.substr(comma+1));
	}
	return value_name;
}

static slot_entries split_value_names(const string &data)
{
	string_list lines = split(data, "\n");
	slot_entries slots;
	sequence_for_each(string_list, linesi, lines) {
		string_list fields = split_value_name(*linesi);
		slots.push_back(make_pair(fields[0], fields[1]));
	}
	return slots;
}

Project::Project(E *e, const string& name) :
	e(e),
	name(name),
	flags(0)
{
	filename = e->projects_path + "/" + name + ".project";
	read();
}

void Project::read(void)
{
	slots.clear();
	if (path_exists(filename)) {
		string data = strip(readpath(filename));
		slot_entries entries = split_value_names(data);
		int slot = 0;
		sequence_for_each(slot_entries, entriesi, entries) {
			Slot *slotp = new Slot(this, slot++,
					entriesi->first, entriesi->second);
			slots.push_back(slotp);
		}
	} else
		slots.push_back(new Slot(this, 0));
}

void Project::write(void)
{
	string data;
	sequence_for_each(slot_list, slotsi, slots) {
		data += (*slotsi)->value + "," + (*slotsi)->name + "\n";
	}
	writepath(filename, data);
}

void Project::exec_current(const string& name_)
{
	if (this == e->current && slots.get(name_) != NULL)
		e->shell->exec_alias(name + "_" + name_);
}

void Project::update_flags(void)
{
	Slot *slot = slots.get("eflags");
	if (slot == NULL)
		return;
	string_list args = split(slot->value);
	string sflags = get_flags(&args);
	flags = 0;
	if (sflags.find('e') != sflags.npos) 
		flags |= no_e_vars;
	if (sflags.find('E') != sflags.npos) 
		flags |= no_global_e_vars;
	if (sflags.find('p') != sflags.npos) 
		flags |= no_project_vars;
	if (sflags.find('P') != sflags.npos) 
		flags |= no_global_vars;
}

void Project::add_environment(void)
{
	update_flags();
	sequence_for_each(slot_list, slotsi, slots) {
		(*slotsi)->add_environment();
	}
	exec_current("init");
}

void Project::delete_environment(void)
{
	update_flags();
	exec_current("deinit");
	sequence_for_each(slot_list, slotsi, slots) {
		(*slotsi)->delete_environment();
	}
}

void Project::clear_name(const string& name)
{
	update_flags();
	sequence_for_each(slot_list, slotsi, slots) {
		Slot *slot = *slotsi;
		if (slot->name == name) {
			slot->delete_environment();
			slot->name = "";
			slot->add_environment();
		}
	}
}

void Project::slot_store(int slot, const string& name, const string& value)
{
	if (slot >= MAX_SLOTS) {
		e->shell->echo("invalid slot %d, max is %d", slot, MAX_SLOTS);
		return;
	}

	if (name != "" && !is_identifier(name)) {
		e->shell->echo("invalid name \"%s\", not an identifier",
				name.c_str());
		return;
	}

	while ((int)slots.size() < slot+1) {
		slots.push_back(new Slot(this, slot));
	}
	Slot *slotp = slots[slot];

	if (name != "")
		clear_name(name);

	if (slotp != NULL) {
		slotp->delete_environment();
		delete slotp;
	}
	slotp = new Slot(this, slot, value, name);
	update_flags();
	slotp->add_environment();
	slots[slot] = slotp;

	slot_list::iterator sli;
	for (sli = slots.end()-1; sli != slots.begin()-1; sli--) {
		slotp = *sli;
		if (slotp->value != "")
			break;
		slots.erase(sli);
		delete slotp;
	}

	write();
}

void Project::slot_name(int slot, const string& name)
{
	if (slot < (int)slots.size())
		slot_store(slot, name, slots[slot]->value);
	else
		slot_store(slot, name, "");
}

void Project::slot_value(int slot, const string& value)
{
	if (slot < (int)slots.size())
		slot_store(slot, slots[slot]->name, value);
	else
		slot_store(slot, "", value);
}

void Project::exchange(int from, int to)
{
	int slot = slots.size();
	while (slot < (from+1) || slot < (to+1)) {
		slots.push_back(new Slot(this, slot++));
	}
	string name = slots[from]->name;
	string value = slots[from]->value;
	slot_store(from, slots[to]->name, slots[to]->value);
	slot_store(to, name, value);

	write();
}

void Project::ls(void)
{
	string s;
	e->shell->echo(YL "%-64s" NO " $name", name.c_str());
	sequence_for_each(slot_list, sli, slots) {
		Slot *slot = *sli;
		s = stringf(CY "%2d" NO ": ", slot->slot);
		if (slot->value.length() > 60) {
			s += stringf("%-56s " RD "... " NO "",
					slot->value.substr(0, 56).c_str());
		} else
			s += stringf("%-60s ", slot->value.c_str());
		if (slot->name != "")
			s += stringf("$%-10s", slot->name.c_str());
		else
			s += stringf("%-11s", "");
		s += stringf(" :" CY "%d" NO, slot->slot);
		e->shell->echo(s.c_str());
	}
}

// ---------------------------------------------------------------
// E methods
// ---------------------------------------------------------------

E::E(int argc, char **argv)
{
	for (int i=1; i<argc; i++) {
		args.push_back(argv[i]);
	}
	e_path = abspath(argv[0]);
	home = environ_get("EHOME", abspath(environ_get("HOME") + "/.e"));
	setup_shell();
	projects_path = home + "/" + shell->name;
	if (!path_exists(projects_path))
		mkdirp(projects_path);
	read_projects();
	current = get_current_project();
}

E::~E(void)
{
	delete shell;
}

void E::setup_shell(void)
{
	//string sh = basepath(environ_get("SHELL", "sh"));
	shell = new Shell(this);
}

void E::read_projects(void)
{
	projects.clear();
	string_list names = globfiles(projects_path + "/*.project");
	sequence_for_each(string_list, sli, names) {
		// remove $EHOME/sh/ and .project
		string name = basepath(sli->substr(0, sli->length()-8));
		projects[name] = new Project(this, name);
	}
}

Project *E::get_current_project(bool use_env)
{
	string eproject = environ_get("EPROJECT");
	string cfile = projects_path + "/current-" + hostname();
	string s;
	if (use_env && eproject.length() != 0)
		s = eproject;
	else if (path_exists(cfile))
		s = split(readpath(cfile), "\n")[0];
	else
		s = "default";
	Project *p = projects.get(s);
	if (p == NULL)
		p = new Project(this, s);
	return p;
}

void E::set_current_project(Project *project, bool local_only)
{
	if (!local_only) {
		string filename;
		filename = projects_path + "/current-" + hostname();
		writepath(filename, project->name + "\n");
	}
	Project *save = current;
	save->delete_environment();
	current = project;
	save->add_environment();
	current->add_environment();
	shell->setenv("EPROJECT", project->name);
}

void E::new_project(const string& name)
{
	Project *project = new Project(this, name);
	string old_filename = project->filename + ".old";
	if (path_exists(old_filename)) {
		rename(old_filename.c_str(), project->filename.c_str());
		project->read();
	}
	projects[name] = project;
	project->write();
}

string_list E::project_names(void)
{
	string_list names;
	sequence_for_each(project_map, pmi, projects) {
		names.push_back(pmi->second->name);
	}
	sort(names.begin(), names.end());
	return names;
}

void E::init(void)
{
	const char **ecommand;
	for (ecommand = ecommands; *ecommand != NULL; ecommand++) {
		shell->eval_alias(e_path, *ecommand, *ecommand);
	}

	current = get_current_project();
	sequence_for_each(project_map, pmi, projects) {
		if (pmi->second != current)
			pmi->second->add_environment();
	}
	current->add_environment();

	shell->setenv("EHOME", home);
	shell->setenv("EPROJECT", current->name);
}

void E::ls(void)
{
	const char *format;
	sequence_for_each(project_map, pmi, projects) {
		if (pmi->second == current)
			format = ">%2d " YL "%-20s " NO;
		else
			format = " %2d " CY "%-20s " NO;
		string s = stringf(format, pmi->second->slots.size(),
					pmi->second->name.c_str());
		shell->echo(s.c_str());
	}
}

void E::eq(void)
{
	shell->unsetenv("EPROJECT");
	shell->unsetenv("EHOME");
	sequence_for_each(project_map, pmi, projects) {
		pmi->second->delete_environment();
	}

	for (const char **ecommand = ecommands; *ecommand != NULL; ecommand++) {
		shell->unalias(*ecommand);
	}
}

void E::ei(void)
{
	init();
}

const char *help_lines[] = {
	CY "ep " YL "[-[tc]] [project]" NO ":",
	"\tdisplay projects, if " YL "project " NO 
		"specified, set it to current",
	CY "erp " YL "project" NO ":",
	"\tremove " YL "project" NO "(if current, default selected)",
	CY "eep " YL "[project]" NO ":",
	"\tedit " YL "project " NO "and reinit (default current)",
	CY "ev " YL "0-# [value]" NO ":",
	"\tstore " YL "value " NO "to slot " YL "0-# " NO
		"(empty value clears)",
	CY "en " YL "0-# [name]" NO ":",
	"\tmake env variable " YL "name " NO "point to slot " YL "#" NO
		" (empty name clears)",
	CY "es " YL "0-# [name] [value]" NO ":",
	"\tmake slot " YL "# " NO "with " YL "name " NO "and "
		YL "value " NO "(empty name & value clears)",
	CY "ec " YL "name [value]" NO ":",
	"\tchange slot with " YL "name " NO "and "
		YL "value " NO "(empty value clears)",
	CY "el " YL "[project]" NO ":",
	"\tlist all slots titles in " YL "project " NO "(default current)",
	CY "em " YL "[-[Aac]]" NO ":",
	"\tlist name,value,proj (-a=all projs,-A name & proj_var,-c=color)",
	CY "ex " YL "from to" NO ":",
	"\texchange slots " YL "from " NO "and " YL "to" NO,
	CY "ei" NO ":\n\t(re)initialize environment and aliases",
	CY "eq" NO ":\n\tremove env and aliases",
	CY "eh" NO ":\n\tprint this help message",
	NULL
};

void E::eh(void)
{
	for (int i = 0; help_lines[i] != NULL; i++) {
		shell->echo(help_lines[i]);
	}
}

void E::el(void)
{
	string name = pop_arg(&args);
	Project *project = projects.get(name);
	if (project == NULL)
		project = current;
	project->ls();
}

static inline void em_slot_all_names(const char *fmt, Shell *shell,
		Slot *slot, const string& name)
{
	string_list names = slot->names();
	sequence_for_each(string_list, namesi, names) {
		shell->echo(fmt, namesi->c_str(),
				slot->value.c_str(), name.c_str());
	}
}

static inline void em_slot(const char *fmt, Shell *shell,
		Slot *slot, const string& name)
{
	shell->echo(fmt, slot->name.c_str(), slot->value.c_str(), name.c_str());
}

void E::em(void)
{
	const char *fmt;
	string_list names;

	string flags = get_flags(&args);
	if (flags.find('a') != flags.npos) {
		names = project_names();
		// TODO: place current at end
	} else
		names.push_back(current->name);

	if (flags.find('c') != flags.npos)
		fmt = CY "$%s" NO ",%s," GR "%s" NO;
	else
		fmt = "$%s,%s,%s";

	sequence_for_each(string_list, namesi, names) {
		Project *project = projects.get(*namesi);
		sequence_for_each(slot_list, slotsi, project->slots) {
			Slot *slot = *slotsi;
			if (flags.find('A') != flags.npos)
				em_slot_all_names(fmt, shell, slot, *namesi);
			else if (slot->name != "")
				em_slot(fmt, shell, slot, *namesi);
		}
	}
}

void E::ep(void)
{
	string flags = get_flags(&args);
	if (args.size() == 0) {
		ls();
		return;
	}
	string name = pop_arg(&args);
	if (!is_identifier(name)) {
		shell->echo("invalid project name \"%s\", not an identifier",
				name.c_str());
		return;
	}

	if (flags.find('c') != flags.npos)
		new_project(name);

	Project *project = projects.get(name);
	if (project != NULL) {
		bool local_only = flags.find('t') != flags.npos;
		set_current_project(project, local_only);
		ls();
	} else
		shell->echo("no project name \"%s\", "
				"use \"ep -c %s\" to create",
				name.c_str(), name.c_str());
}

void E::erp(void)
{
	if (args.size() == 0) {
		shell->echo("usage: erp project");
		return;
	}

	string name = pop_arg(&args);
	if (name == "default") {
		shell->echo("cannot remove project \"default\"");
		return;
	}

	project_map::iterator projectsi = projects.find(name);
	if (projectsi == projects.end()) {
		shell->echo("project \"%s\" does not exist", name.c_str());
		return;
	}
	projects.erase(projectsi);

	Project *project = projectsi->second;
	project->delete_environment();
	if (project == current)
		set_current_project(projects.get("default"));

	string new_filename = project->filename + ".old";
	rename(project->filename.c_str(), new_filename.c_str());

	delete project;

	ls();
}

void E::eep(void)
{
	string name = current->name;
	if (args.size() > 0)
		name = pop_arg(&args);

	Project *project = projects.get(name);
	if (project == NULL) {
		project = new Project(this, name);
		projects[name] = project;
	}
	project->delete_environment();
	string editor = environ_get("EDITOR", "vi").c_str();
	printf("%s %s;ei\n", editor.c_str(), project->filename.c_str());
}

void E::es(void)
{
	int slot = integer(pop_arg(&args), -1);
	if (slot < 0)
		shell->echo("usage: es slot [name] [value]");
	else {
		string name = pop_arg(&args);
		string value;
		if (args.size() > 0)
			value = join(args, " ");
		current->slot_store(slot, name, value);
	}
}

void E::en(void)
{
	int slot = integer(pop_arg(&args), -1);
	if (slot < 0)
		shell->echo("usage: en slot [name]");
	else
		current->slot_name(slot, pop_arg(&args));
}

void E::ev(void)
{
	int slot = integer(pop_arg(&args), -1);
	if (slot < 0)
		shell->echo("usage: en slot [value]");
	else 
		current->slot_value(slot, join(args, " "));
}

void E::ec(void)
{
	if (args.size() < 1)
		shell->echo("usage: ec name [value]");
	else {
		string name = pop_arg(&args);
		string value = join(args, " ");
		sequence_for_each(slot_list, slotsi, current->slots) {
			Slot *slot = *slotsi;
			if (slot->name == name)
				current->slot_value(slot->slot, value);
		}
	}
}

void E::ex(void)
{
	int from = integer(pop_arg(&args), -1);
	int to = integer(pop_arg(&args), -1);
	if (from < 0 || to < 0)
		shell->echo("usage: ex slot slot");
	else
		current->exchange(from, to);

}

int E::process(void)
{
	string cmd = pop_arg(&args);
	if (cmd == "init")	init();
	else if (cmd == "eq")	eq();
	else if (cmd == "ei")	ei();
	else if (cmd == "eh")	eh();
	else if (cmd == "el")	el();
	else if (cmd == "em")	em();
	else if (cmd == "ep")	ep();
	else if (cmd == "erp")	erp();
	else if (cmd == "eep")	eep();
	else if (cmd == "es")	es();
	else if (cmd == "en")	en();
	else if (cmd == "ev")	ev();
	else if (cmd == "ex")	ex();
	return 0;
}

int main(int argc, char **argv)
{
	E *e = new E(argc, argv);
	int rc = e->process();
	delete e;
	return rc;
}

