#ifndef ERLTLS_C_SRC_MACROS_H_
#define ERLTLS_C_SRC_MACROS_H_

#define UNUSED(expr) do { (void)(expr); } while (0)

#define DISALLOW_ASSIGN(TypeName) void operator=(const TypeName&)
#define DISALLOW_COPY_AND_ASSIGN(TypeName) TypeName(const TypeName&); DISALLOW_ASSIGN(TypeName)
#define DISALLOW_IMPLICIT_CONSTRUCTORS(TypeName) TypeName(); DISALLOW_COPY_AND_ASSIGN(TypeName)

#endif