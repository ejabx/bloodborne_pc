#include "runtime.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef int32_t (ABI *Allocate)(int64_t, int64_t, uint64_t, uint64_t, int, int64_t *);
typedef int32_t (ABI *Map)(void **, uint64_t, int, int, int64_t, uint64_t);
typedef int32_t (ABI *Unmap)(void *, uint64_t);
typedef int32_t (ABI *Release)(uint64_t, uint64_t);
typedef int32_t (ABI *Reserve)(void **, uint64_t, int, uint64_t);

/* This standalone test resolves a named export without linking the full runtime. */
uintptr_t runtime_lookup(const RuntimeExport *table, size_t count, const char *nid) {
    for (size_t i=0; i<count; ++i)
        if (!strcmp(table[i].name,nid)) return (uintptr_t)table[i].function;
    return 0;
}

int main(void) {
    const uint64_t size=16384;
    Allocate allocate=(Allocate)runtime_memory_resolve("rTXw65xmLIA#p#J");
    Map map=(Map)runtime_memory_resolve("L-Q3LEjIbgA#p#J");
    Unmap unmap=(Unmap)runtime_memory_resolve("cQke9UuBQOk#p#J");
    Release release=(Release)runtime_memory_resolve("MBuItvba6z8#p#J");
    Reserve reserve=(Reserve)runtime_memory_resolve("sceKernelReserveVirtualRange");
    assert(allocate && map && unmap && release && reserve);
    int64_t physical=-1, replacement=-1;
    assert(allocate(0,512*1024*1024,size,0,0,&physical)==0);
    assert(allocate(0,512*1024*1024,size,0,0,&replacement)==0);
    void *first=NULL, *alias=NULL;
    assert(map(&first,size,3,0,physical,2097152)==0);
    assert(map(&alias,size,3,0,physical,0)==0);
    assert((uintptr_t)first<UINT64_C(0x10000000000));
    assert((uintptr_t)first%2097152==0);
    *(uint64_t *)first=UINT64_C(0x123456789abcdef0);
    assert(*(uint64_t *)alias==UINT64_C(0x123456789abcdef0));
    void *fixed=first;
    int32_t result=map(&fixed,size,3,0x10,replacement,0);
    if (result) {
        fprintf(stderr,"FAIL: fixed replacement at owned address returned 0x%x\n",(unsigned)result);
        return 1;
    }
    assert(fixed==first);
    assert(*(uint64_t *)fixed==0);
    assert(*(uint64_t *)alias==UINT64_C(0x123456789abcdef0));
    assert(unmap(first,size)==0);
    fixed=first;
    result=map(&fixed,size,3,0x10,replacement,0);
    if (result) {
        fprintf(stderr,"FAIL: fixed map into freed owned address returned 0x%x\n",(unsigned)result);
        return 1;
    }
    assert(fixed==first);
    assert(unmap(fixed,size)==0);
    void *reserved=NULL;
    assert(reserve(&reserved,size,0,0)==0);
    fixed=reserved;
    assert(map(&fixed,size,3,0x10,replacement,0)==0);
    assert(fixed==reserved);
    assert(unmap(fixed,size)==0);
    assert(unmap(alias,size)==0);
    assert(release((uint64_t)physical,size)==0);
    assert(release((uint64_t)replacement,size)==0);
    puts("PASS: Rosetta direct memory placement, alias, and fixed maps at owned addresses");
    return 0;
}
