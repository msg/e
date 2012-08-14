//
// p a t h . h
//
#ifndef _PATH_H
#define _PATH_H
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 500
#endif

#include <stdio.h>
#include <alloca.h>
#include <limits.h>
#include <stdlib.h>
#include <unistd.h>
#include <libgen.h>
#include <glob.h>
#include <ftw.h>
#include <sys/types.h>
#include <sys/stat.h>
#include "stringfuncs.h"

// readpath - read contents of path into string and return it.
inline string readpath(const string& path)
{
	int rc = 4<<10;
	char buf[rc];
        FILE *file;
	string s;

        file = fopen(path.c_str(), "r");
        if (file == NULL)
		return "";

	while (1) {
		rc = fread(buf, 1, rc, file);
		if (rc <= 0)
			break;
		s += string(buf, rc);
	}
	fclose(file);

        return strip(s);
}

// getfile - allocate and read path into bufp
inline int getfile(const string &path, char **bufpp)
{
	FILE *file;
	int size, rc;
	file = fopen(path.c_str(), "r");
	if (file == NULL)
		return -1;
	fseek(file, 0, SEEK_END);
	size = ftell(file);
	fseek(file, 0, SEEK_SET);
	*bufpp = new char[size];
	rc = fread(*bufpp, 1, size, file);
	fclose(file);
	if (rc != size) {
		delete[] *bufpp;
		*bufpp = NULL;
		rc = 0;
	}
	return rc;
}

// writepath - write string data to path
inline int writepath(const string& path, const string& data)
{
        FILE *file;
        int rc = 0;

        file = fopen(path.c_str(), "w");
        if (!file)
		return -1;

	rc = fwrite(data.c_str(), 1, data.length(), file);
	fclose(file);

        return rc;
}

// abspath - return the "real" path.
inline string abspath(const string& path)
{
	char buf[PATH_MAX];
	const char *p = NULL;
	if (path != "")
		p = realpath(path.c_str(), buf);
	if (p == NULL)
		p = "";
	return string(p);
}

// basepath - return path from after final /
inline string basepath(const string& path)
{
	if (path != "") {
		char buf[PATH_MAX];
		strncpy(buf, path.c_str(), path.size()+1);
		return basename(buf);
	} else
		return "";
}

// dirpath - return path upto final /
inline string dirpath(const string& path)
{
	string s = path;
	if (path != "") {
		char buf[s.size()+1];
		strncpy(buf, s.c_str(), s.size()+1);
		const char *p = dirname(buf);
		return p;
	} else
		return "";
}

// path_exists - return 0 if path exists, -1 on error
inline int path_exists(const string& path)
{
	struct stat st;
	return stat(path.c_str(), &st) == 0;
}

// mkdirp - emulate shell mkdir -p 
inline int mkdirp(const string& path, int permissions=0755)
{
	string dir = dirpath(path);
	if (dir.length() == 0)
		return 0;
	while (!path_exists(dir)) {
		int rc = mkdirp(dir, permissions);
		if (rc < 0)
			return rc;
	}
	if (!path_exists(path.c_str()))
		return mkdir(path.c_str(), permissions);
	else
		return 0;
}

// globfiles - return list of glob'd files
string_list globfiles(const string& globs)
{
	string_list files;
	glob_t *globp;
	size_t i;

	globp = new glob_t();
	globp->gl_offs = 0;
	glob(globs.c_str(), GLOB_DOOFFS, NULL, globp);

	for (i = 0; i < globp->gl_pathc; i++) {
		files.push_back(globp->gl_pathv[i]);
	}
	globfree(globp);
	return files;
}


// nrm - helper for rmrf below
inline int nrm(const char *path, const struct stat *sp, int flag,
		struct FTW *ftwp)
{
	if (flag == FTW_F || flag == FTW_SL)
		return unlink(path);
	else
		return rmdir(path);
	return 0;
}

// rmrf - emulate shell rm -rf
inline int rmrf(const string& path)
{
	return nftw(path.c_str(), nrm, 5, FTW_DEPTH | FTW_PHYS);
}

// writen - write all of len chars from buf return how many or error.
inline int writen(int fd, char *buf, int len)
{
	int rc = 0;
	int nleft = len;
	while (nleft > 0) {
		rc = write(fd, buf, nleft);
		if (rc <= 0)
			return rc;
		buf += rc;
		nleft -= rc;
	}
	return (len != nleft) ? len - nleft : rc;
}

#endif // _PATH_H

