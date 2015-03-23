// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.fileutil;

import visuald.windows;

import stdext.array;
import stdext.file;
import stdext.path;
import stdext.string;

import std.algorithm;
import std.path;
import std.file;
import std.string;
import std.conv;
import std.utf;

//-----------------------------------------------------------------------------
long[string] gCachedFileTimes;
alias AssociativeArray!(string, long) _wa1; // fully instantiate type info

void clearCachedFileTimes()
{
	long[string] empty;
	gCachedFileTimes = empty; // = gCachedFileTimes.init;
}

void removeCachedFileTime(string file)
{
	file = canonicalPath(file);
	gCachedFileTimes.remove(file);
}

//-----------------------------------------------------------------------------
void getOldestNewestFileTime(string[] files, out long oldest, out long newest, out string oldestFile, out string newestFile)
{
	oldest = long.max;
	newest = long.min;
	foreach(file; files)
	{
		file = canonicalPath(file);
		long ftm;
		if(auto ptm = file in gCachedFileTimes)
			ftm = *ptm;
		else
		{
			if(!exists(file))
			{
			L_fileNotFound:
				oldest = long.min;
				newest = long.max;
				oldestFile = newestFile = file;
				break;
			}
version(all)
			ftm = timeLastModified(file).stdTime();
else
{
			WIN32_FILE_ATTRIBUTE_DATA fad;
			if(!GetFileAttributesExW(std.utf.toUTF16z(file), /*GET_FILEEX_INFO_LEVELS.*/GetFileExInfoStandard, &fad))
				goto L_fileNotFound;
			ftm = *cast(long*) &fad.ftLastWriteTime;
}
			gCachedFileTimes[file] = ftm;
		}
		if(ftm > newest)
		{
			newest = ftm;
			newestFile = file;
		}
		if(ftm < oldest)
		{
			oldest = ftm;
			oldestFile = file;
		}
	}
}

long getNewestFileTime(string[] files, out string newestFile)
{
	string oldestFile;
	long oldest, newest;
	getOldestNewestFileTime(files, oldest, newest, oldestFile, newestFile);
	return newest;
}

long getOldestFileTime(string[] files, out string oldestFile)
{
	string newestFile;
	long oldest, newest;
	getOldestNewestFileTime(files, oldest, newest, oldestFile, newestFile);
	return oldest;
}

bool compareCommandFile(string cmdfile, string cmdline)
{
	try
	{
		if(!exists(cmdfile))
			return false;
		string lastCmd = cast(string)std.file.read(cmdfile);
		if (strip(cmdline) != strip(lastCmd))
			return false;
	}
	catch(Exception)
	{
		return false;
	}
	return true;
}

bool moveFileToRecycleBin(string fname)
{
	SHFILEOPSTRUCT fop;
	fop.wFunc = FO_DELETE;
	fop.fFlags = FOF_NO_UI | FOF_NORECURSION | FOF_FILESONLY | FOF_ALLOWUNDO;
	wstring wname = to!wstring(fname);
	wname ~= "\000\000";
	fop.pFrom = wname.ptr;

	if(SHFileOperation(&fop) != 0)
		return false;
	return !fop.fAnyOperationsAborted;
}

string shortFilename(string fname)
{
	wchar* sptr;
	auto wfname = toUTF16z(fname);
	wchar[256] spath;
	DWORD len = GetShortPathNameW(wfname, spath.ptr, spath.length);
	if(len > spath.length)
	{
		wchar[] sbuf = new wchar[len];
		len = GetShortPathNameW(wfname, sbuf.ptr, sbuf.length);
		sptr = sbuf.ptr;
	}
	else
		sptr = spath.ptr;
	if(len == 0)
		return "";
	return to!string(sptr[0..len]);
}

string[] findDRuntimeFiles(string path, string sub, bool deep, bool cfiles = false, bool internals = false)
{
	string[] files;
	if(!isExistingDir(path ~ sub))
		return files;
	foreach(string file; dirEntries(path ~ sub, SpanMode.shallow))
	{
		if(_startsWith(file, path))
			file = file[path.length .. $];
		if (deep && isExistingDir(path ~ file))
		{
			string[] exclude = [ "\\internal", "\\freebsd", "\\linux", "\\osx", "\\posix", "\\solaris" ];
			if (internals)
				exclude = exclude[1..$];
			if (!any!(e => file.endsWith(e))(exclude))
				files ~= findDRuntimeFiles(path, file, deep, cfiles);
			continue;
		}
		string bname = baseName(file);
		if(globMatch(bname, "openrj.d"))
			continue;
		if(globMatch(bname, "minigzip.c") || globMatch(bname, "example.c"))
			continue;
		if(cfiles)
		{
			if(globMatch(bname, "*.c"))
				if(!contains(files, file))
					files ~= file;
		}
		else if(globMatch(bname, "*.d"))
			if(string* pfile = contains(files, file ~ "i"))
				*pfile = file;
			else
				files ~= file;
		else if(globMatch(bname, "*.di"))
		{
			// use the d file instead if available
			string dfile = "..\\src\\" ~ file[0..$-1];
			if(std.file.exists(path ~ dfile))
				file = dfile;
			if(!contains(files, file[0..$-1]))
				files ~= file;
		}
	}
	return files;
}

