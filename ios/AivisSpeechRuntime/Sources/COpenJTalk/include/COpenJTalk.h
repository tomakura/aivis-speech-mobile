#ifndef COPENJTALK_H
#define COPENJTALK_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct COpenJTalk COpenJTalk;

typedef struct COpenJTalkNode {
    const char *surface;
    const char *pronunciation;
    const char *part_of_speech;
    int accent;
    int mora_size;
    int chain_flag;
} COpenJTalkNode;

typedef void (*COpenJTalkNodeCallback)(const COpenJTalkNode *node, void *context);
typedef void (*COpenJTalkLabelCallback)(const char *label, void *context);

COpenJTalk *copenjtalk_create(const char *dictionary_path, char *error_buffer, int error_buffer_size);
void copenjtalk_destroy(COpenJTalk *handle);

int copenjtalk_run_frontend(
    COpenJTalk *handle,
    const char *text,
    COpenJTalkNodeCallback callback,
    void *context,
    char *error_buffer,
    int error_buffer_size
);

int copenjtalk_make_labels(
    COpenJTalk *handle,
    const char *text,
    COpenJTalkLabelCallback callback,
    void *context,
    char *error_buffer,
    int error_buffer_size
);

#ifdef __cplusplus
}
#endif

#endif
