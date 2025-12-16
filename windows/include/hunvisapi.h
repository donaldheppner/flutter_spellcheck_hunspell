#ifndef _HUNVISAPI_H_
#define _HUNVISAPI_H_

#if defined(HUNSPELL_STATIC)
#  define LIBHUNSPELL_DLL_EXPORTED
#elif defined(_MSC_VER)
#  ifdef LIBHUNSPELL_EXPORTS
#    define LIBHUNSPELL_DLL_EXPORTED __declspec(dllexport)
#  else
#    define LIBHUNSPELL_DLL_EXPORTED __declspec(dllimport)
#  endif
#else
#  define LIBHUNSPELL_DLL_EXPORTED
#endif

#endif
