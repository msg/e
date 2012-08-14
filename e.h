//
// e . h
//
#ifndef _E_H
#define _E_H

#include <string>
#include <vector>
#include <map>

using std::string;
using std::vector;
using std::map;

#define sequence_for_each(type, iter, seq) \
	for (type::iterator iter = seq.begin(); iter != seq.end(); iter++)
#define sequence_for_each_reverse(type, iter, seq) \
	for (type::iterator iter = seq.rbegin(); iter != seq.rend(); iter++)

class E;
class Project;
class Slot;

typedef vector<string> string_list;
typedef map<string, string> string_map;

class project_map : public map<string, Project *> {
public:
	Project *get(const string& name) {
		project_map::iterator projectsi = find(name);
		if (projectsi != end())
			return projectsi->second;
		return NULL;
	}
};

class Shell {
public:
	Shell(E *e_) : e(e_) { name = "sh"; }
	virtual ~Shell(void) { }

	void setenv(const string& name, const string& value);
	void unsetenv(const string& name);
	void alias(const string& name, const string& value);
	void unalias(const string& name);
	void eval_alias(const string& path, const string& name,
			const string& value);
	void setenv_alias(const string& name, const string& value);
	void unsetenv_alias(const string& name);
	void exec_alias(const string& name);
	void echo(const char *fmt, ...);

	E *e;
	string name;
};

class Slot {
public:
	Slot(Project *project_, int slot_,
		const string& value_="", const string& name_="");
	virtual ~Slot(void) { }

	// methods
	string_list names(void);
	void add_environment(void);
	void delete_environment(void);
	
	// members
	Project *project;
	int slot;
	string value;
	string name;
};

class slot_list : public vector<Slot *> {
public:
	Slot *get(const string& name)
	{
		slot_list &slots = *this;
		sequence_for_each(slot_list, slotsi, slots) {
			if ((*slotsi)->name == name)
				return *slotsi;
		}
		return NULL;
	}
};

enum project_flags {
	no_e_vars		= 0x0001,
	no_global_e_vars	= 0x0002,
	no_project_vars		= 0x0004,
	no_global_vars		= 0x0008,
};

class Project {
public:
	Project(E *e, const string& name);
	virtual ~Project(void) { }

	// methods
	void read(void);
	void write(void);
	void extend(int size);
	void update_flags(void);
	void exec_current(const string& name);
	void add_environment(void);
	void delete_environment(void);
	void clear_name(const string& name);
	void slot_store(int slot, string name, string value);
	void slot_name(int slot, const string& name);
	void slot_value(int slot, const string& value);
	void exchange(int fromslot, int toslot);
	void ls(void);

	// members
	E *e;
	string name;
	string filename;
	slot_list slots;
	int flags;
};

class E {
public:
	E(int argc, char **argv);
	virtual ~E(void);

	// methods
	void setup_shell(void);
	void read_projects(void);
	Project * get_current_project(bool use_env=true);
	void set_current_project(Project *project, bool local_only=false);
	void new_project(const string& name);
	string_list project_names(void);
	void init(void);
	void ls(void);
	void eq(void);
	void ei(void);
	void eh(void);
	void el(void);
	void em(void);
	void ep(void);
	void erp(void);
	void eep(void);
	void es(void);
	void en(void);
	void ev(void);
	void ec(void);
	void ex(void);
	int process(void);

	// members
	string_list args;
	string home;
	string projects_path;
	string e_path;
	Shell *shell;
	project_map projects;
	Project *current;
	string_map variables;
};

#endif // _E_H

