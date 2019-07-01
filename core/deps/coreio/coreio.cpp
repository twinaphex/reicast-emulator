
#include "coreio.h"

#include <time.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <sstream>
#include <string>
#include <iomanip>
#include <cctype>
#include <streams/file_stream.h>

#define TRUE 1
#define FALSE 0


#include <string>
#include <sstream>

struct CORE_FILE {
	RFILE *f;

	string path;
	size_t seek_ptr;

	string host;
	int port;
};

core_file* core_fopen(const char* filename)
{
	string p = filename;

	CORE_FILE* rv = new CORE_FILE();
	rv->f = 0;
	rv->path = p;

	rv->f = filestream_open(filename, RETRO_VFS_FILE_ACCESS_READ, RETRO_VFS_FILE_ACCESS_HINT_NONE);

	if (!rv->f) {
		delete rv;
		return 0;
	}

	core_fseek((core_file*)rv, 0, SEEK_SET);
	return (core_file*)rv;
}

size_t core_fseek(core_file* fc, size_t offs, size_t origin) {
	CORE_FILE* f = (CORE_FILE*)fc;
	
	if (origin == SEEK_SET)
		f->seek_ptr = offs;
	else if (origin == SEEK_CUR)
		f->seek_ptr += offs;
	else
		die("Invalid code path");

	if (f->f)
		filestream_seek(f->f, f->seek_ptr, RETRO_VFS_SEEK_POSITION_START);

	return 0;
}

size_t core_ftell(core_file* fc)
{
	CORE_FILE* f = (CORE_FILE*)fc;
	return f->seek_ptr;
}
int core_fread(core_file* fc, void* buff, size_t len)
{
	CORE_FILE* f = (CORE_FILE*)fc;
	if (f->f)
		filestream_read(f->f, buff, len);

	f->seek_ptr += len;

	return len;
}

int core_fclose(core_file* fc)
{
   CORE_FILE* f = (CORE_FILE*)fc;

   if (f->f)
   	filestream_close(f->f);

   delete f;

   return 0;
}

size_t core_fsize(core_file* fc)
{
   CORE_FILE* f = (CORE_FILE*)fc;

   if (f->f) {
   	size_t p = filestream_tell(f->f);
   	filestream_seek(f->f, 0, RETRO_VFS_SEEK_POSITION_END);
		size_t rv = filestream_tell(f->f);
      filestream_seek(f->f, p, RETRO_VFS_SEEK_POSITION_START);
      return rv;
   }
   return 0;
}
