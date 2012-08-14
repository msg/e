//
// s t r i n g f u n c s . h
//
#ifndef _STRINGFUNCS_H
#define _STRINGFUNCS_H
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <vector>
#include <deque>
#include <algorithm>
#include <string>

using std::string;

inline string get_line(string *s, char delim='\n')
{
	string::size_type nl = s->find(delim);
	string ns = s->substr(0, nl+1);
	s->erase(0, nl+1);
	return ns;
}

inline string get_token(string *s, const string& sep=" \t\n\r")
{
	string::size_type start = s->find_first_not_of(sep);
	if (start == s->npos) {
		s->erase();
		return "";
	}
	string::size_type end = s->find_first_of(sep, start);
	string ns = s->substr(start, end-start);
	s->erase(0, end);
	return ns;
}

typedef std::vector<string> string_list;

inline string_list split(const string& s, const string& sep = " \t\r\n",
		unsigned int max = 1024)
{
	string::size_type sepl = 0;
	string::size_type nsepl = 0;
	string_list fields;
	int l = s.length();
	while (l > 0 && sepl != s.npos && max--) {
		sepl = s.find_first_of(sep, nsepl);
		fields.push_back(s.substr(nsepl, sepl-nsepl));
		nsepl = sepl + 1;
	}
	return fields;
}

// "C" char * implementation for speed
inline int csplit(char *s, int l, const char *sep, char **sp, int n)
{
	char *e = s + l;
	int m = 0;
	for (m=0; s < e && m < n; m++) {
		*sp++ = s;
		s += strcspn(s, sep);		// find length of non-sep's
		*s++ = '\0';			// null terminate field
		s += strspn(s, sep);		// find length of sep's
	}
	return m; // return total number of fields found
}

// clstrip - strip ws at left(front) of string
//    char *s - string to strip
//    int l - length of string (not including '\0' but assumed to be there)
inline char *clstrip(char *s, int l)
{
	char *e = s + l;
	while (s < e && isspace(*s))
		s++;
	return s;
}

// crstrip - strip ws at right(end) of string, return new string length
//    char *s - string to strip
//    int l - length of string (not including '\0' but assumed to be there)
inline int crstrip(char *s, int l)
{
	char *e = s + l - 1;
	while (e > s && isspace(*e))
		e--;
	*++e = '\0';
	return e - s;
}

inline char *join(char *s, int l, char **fs, int n)
{
	char *e = s + l - 1;
	char *f;
	int i;
	for (i=0; s < e && i < n; i++, fs++) {
		f = *fs;
		while (*f) {
			*s++ = *f++;
		}
	}
	*s = '\0';
	return s;
}

inline string join(const string_list& fields, const string &sep)
{
	string_list::const_iterator fli, fle = fields.end();
	string s;
	for (fli = fields.begin(),fle--; fli != fle; fli++) {
		s.append(*fli);
		s.append(sep);
	}
	s.append(*fli);
	return s;
}

inline string lstrip(const string& s, const string& strips=" \t\n\r")
{
	string::size_type start = s.find_first_not_of(strips);
	if (start != s.npos)
		return s.substr(s.find_first_not_of(strips));
	return s;
}

inline string rstrip(const string& s, const string& strips=" \t\n\r")
{
	string::size_type end = s.find_last_not_of(strips);
	if (end != s.npos)
		return s.substr(0,end+1);
	return s;
}

inline string strip(const string& s, const string& strips=" \t\n\r")
{
	return lstrip(rstrip(s, strips), strips);
}

inline bool starts_with (const string& s, const string &with)
{
	return s.substr(0,with.length()) == with;
}

inline bool ends_with (const string& s, const string &with)
{
	if (s.length() < with.length())
		return false;
	return s.substr(s.length()-with.length()) == with;
}

inline unsigned int unsigned_integer(const string& s, unsigned int dflt=0)
{
	char *ep;
	unsigned int i;
	i = strtoul(s.c_str(), &ep, 0);
	if (ep != s.c_str())
		return i;
	else
		return dflt;
}

inline int integer(const string& s, int dflt=0)
{
	char *ep;
	int i;
	i = strtol(s.c_str(), &ep, 0);
	if (ep != s.c_str())
		return i;
	else
		return dflt;
}

inline long long longlong(const string& s, long long dflt=0)
{
	char *ep;
	long long ll;
	ll = strtoll(s.c_str(), &ep, 0);
	if (ep != s.c_str())
		return ll;
	else
		return dflt;
}

inline int parse_byte(const string& s, long long *size)
{
	char *ep;
	*size = strtoll(s.c_str(), &ep, 0);
	if (s.c_str() == ep)
		return -1;
	switch (tolower(*ep)) {
		case 'k': *size <<= 10; break;
		case 'm': *size <<= 20; break;
		case 'g': *size <<= 30; break;
		case 't': *size <<= 40; break;
		case 'p': *size <<= 50; break;
		case 0:
			  break;
		default:
			  return -1;
	}
	return 0;
}


string vstringf(const char *fmt, va_list ap)
	__attribute__ ((format (printf, 1, 0)));

inline string vstringf(const char *fmt, va_list ap)
{
	va_list nap;
	va_copy(nap, ap);
	int l = vsnprintf(0, 0, fmt, nap);
	va_end(nap);
	char buf[l+1];
	va_copy(nap, ap);
	vsnprintf(buf, l+1, fmt, nap);
	va_end(nap);
	return buf;
}

string stringf(const char *fmt, ...)
	__attribute__ ((format (printf, 1, 2)));


inline string stringf(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	int l = vsnprintf(0, 0, fmt, ap);
	va_end(ap);
	char buf[l+1];
	va_start(ap, fmt);
	vsnprintf(buf, l+1, fmt, ap);
	va_end(ap);
	return buf;
}

inline string tolower_string(const string& str)
{
	string s = str;
	transform(s.begin(), s.end(), s.begin(), ::tolower);
	return s;
}

inline string toupper_string(const string& str)
{
	string s = str;
	transform(s.begin(), s.end(), s.begin(), ::toupper);
	return s;
}

#endif // _STRINGFUNCS_H

