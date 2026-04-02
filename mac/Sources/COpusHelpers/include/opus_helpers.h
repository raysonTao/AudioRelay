#ifndef OPUS_HELPERS_H
#define OPUS_HELPERS_H

#include "/opt/homebrew/include/opus/opus.h"

/// Reset the Opus decoder state (wraps variadic opus_decoder_ctl).
static inline int opus_helpers_decoder_reset(OpusDecoder *decoder) {
    return opus_decoder_ctl(decoder, OPUS_RESET_STATE);
}

#endif
