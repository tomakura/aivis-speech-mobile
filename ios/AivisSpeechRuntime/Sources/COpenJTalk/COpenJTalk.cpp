#include "COpenJTalk.h"

#include <cerrno>
#include <cstring>
#include <new>

#include "mecab.h"
#include "njd.h"
#include "mecab2njd.h"
#include "njd_set_accent_phrase.h"
#include "njd_set_accent_type.h"
#include "njd_set_digit.h"
#include "njd_set_long_vowel.h"
#include "njd_set_pronunciation.h"
#include "njd_set_unvoiced_vowel.h"
#include "jpcommon.h"
#include "njd2jpcommon.h"
#include "text2mecab.h"

struct COpenJTalk {
    Mecab mecab;
    NJD njd;
    JPCommon jpcommon;
};

static void write_error(char *error_buffer, int error_buffer_size, const char *message)
{
    if (error_buffer == nullptr || error_buffer_size <= 0) {
        return;
    }
    if (message == nullptr) {
        message = "OpenJTalk error";
    }
    std::strncpy(error_buffer, message, static_cast<size_t>(error_buffer_size - 1));
    error_buffer[error_buffer_size - 1] = '\0';
}

COpenJTalk *copenjtalk_create(const char *dictionary_path, char *error_buffer, int error_buffer_size)
{
    if (dictionary_path == nullptr || std::strlen(dictionary_path) == 0) {
        write_error(error_buffer, error_buffer_size, "OpenJTalk dictionary path is empty");
        return nullptr;
    }

    COpenJTalk *handle = new (std::nothrow) COpenJTalk;
    if (handle == nullptr) {
        write_error(error_buffer, error_buffer_size, "Failed to allocate OpenJTalk handle");
        return nullptr;
    }

    Mecab_initialize(&handle->mecab);
    NJD_initialize(&handle->njd);
    JPCommon_initialize(&handle->jpcommon);

    if (Mecab_load(&handle->mecab, const_cast<char *>(dictionary_path)) != TRUE) {
        JPCommon_clear(&handle->jpcommon);
        NJD_clear(&handle->njd);
        Mecab_clear(&handle->mecab);
        delete handle;
        write_error(error_buffer, error_buffer_size, "Failed to load OpenJTalk dictionary");
        return nullptr;
    }

    return handle;
}

void copenjtalk_destroy(COpenJTalk *handle)
{
    if (handle == nullptr) {
        return;
    }
    JPCommon_clear(&handle->jpcommon);
    NJD_clear(&handle->njd);
    Mecab_clear(&handle->mecab);
    delete handle;
}

static int run_njd_pipeline(
    COpenJTalk *handle,
    const char *text,
    char *error_buffer,
    int error_buffer_size
) {
    if (handle == nullptr) {
        write_error(error_buffer, error_buffer_size, "OpenJTalk handle is null");
        return 0;
    }
    if (text == nullptr || std::strlen(text) == 0) {
        write_error(error_buffer, error_buffer_size, "OpenJTalk text is empty");
        return 0;
    }

    char mecab_text[8192];
    const text2mecab_result_t conversion_result = text2mecab(mecab_text, sizeof(mecab_text), text);
    if (conversion_result != TEXT2MECAB_RESULT_SUCCESS) {
        if (conversion_result == TEXT2MECAB_RESULT_RANGE_ERROR) {
            write_error(error_buffer, error_buffer_size, "OpenJTalk text is too long");
        } else {
            write_error(error_buffer, error_buffer_size, "OpenJTalk text conversion failed");
        }
        return 0;
    }

    if (Mecab_analysis(&handle->mecab, mecab_text) != TRUE) {
        write_error(error_buffer, error_buffer_size, "OpenJTalk MeCab analysis failed");
        return 0;
    }

    mecab2njd(&handle->njd, Mecab_get_feature(&handle->mecab), Mecab_get_size(&handle->mecab));
    njd_set_pronunciation(&handle->njd);
    njd_set_digit(&handle->njd);
    njd_set_accent_phrase(&handle->njd);
    njd_set_accent_type(&handle->njd);
    njd_set_unvoiced_vowel(&handle->njd);
    njd_set_long_vowel(&handle->njd);
    return 1;
}

int copenjtalk_run_frontend(
    COpenJTalk *handle,
    const char *text,
    COpenJTalkNodeCallback callback,
    void *context,
    char *error_buffer,
    int error_buffer_size
) {
    if (run_njd_pipeline(handle, text, error_buffer, error_buffer_size) != 1) {
        return 0;
    }

    if (callback != nullptr) {
        for (NJDNode *node = handle->njd.head; node != nullptr; node = node->next) {
            const COpenJTalkNode bridge_node = {
                NJDNode_get_string(node),
                NJDNode_get_pron(node),
                NJDNode_get_pos(node),
                NJDNode_get_acc(node),
                NJDNode_get_mora_size(node),
                NJDNode_get_chain_flag(node),
            };
            callback(&bridge_node, context);
        }
    }

    NJD_refresh(&handle->njd);
    Mecab_refresh(&handle->mecab);
    return 1;
}

int copenjtalk_make_labels(
    COpenJTalk *handle,
    const char *text,
    COpenJTalkLabelCallback callback,
    void *context,
    char *error_buffer,
    int error_buffer_size
) {
    if (run_njd_pipeline(handle, text, error_buffer, error_buffer_size) != 1) {
        return 0;
    }

    njd2jpcommon(&handle->jpcommon, &handle->njd);
    JPCommon_make_label(&handle->jpcommon);

    if (callback != nullptr) {
        const int label_size = JPCommon_get_label_size(&handle->jpcommon);
        char **labels = JPCommon_get_label_feature(&handle->jpcommon);
        for (int index = 0; index < label_size; ++index) {
            callback(labels[index], context);
        }
    }

    JPCommon_refresh(&handle->jpcommon);
    NJD_refresh(&handle->njd);
    Mecab_refresh(&handle->mecab);
    return 1;
}
