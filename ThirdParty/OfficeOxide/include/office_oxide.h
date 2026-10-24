#include <stdint.h>
#include <stddef.h>
typedef struct OfficeDocumentHandle OfficeDocumentHandle;
OfficeDocumentHandle *office_document_open_from_bytes(const uint8_t *, size_t, const char *, int *);
char *office_document_to_ir_json(const OfficeDocumentHandle *, int *);
void office_document_free(OfficeDocumentHandle *);
void office_oxide_free_string(char *);
